module DeadViewCatcher
  
  # DeadViewCatcher help you find easily not used views in your Rails app.
  # It's not really Thread safe and using globals, but it's on purpose.
  
  # Usage:
  #
  # Send a signal (TRAP by default) to one of your rails instance in order to create a dump of the dead views in tmp/dead_views.txt
  #   kill -s TRAP pid
  #
  # If you want a more globalized stats, you can use the all instances signal (URG by default)
  # This signal will agregate the results of all instances by sending to all instances the TRAP signal.
  # Then it will dump the consolidated stats in tmp/dead_views.txt (the default file)
  #
  # Note: SIGUSR1 and SIGUSR2 is not used as it's used by unicorn :/

  DefaultOptions = {:signal => 'TRAP', :file => 'tmp/dead_views.txt', :all_instances_signal => 'URG'}

  def self.watch!(opts = {})
    options = DefaultOptions.merge(opts)

    $dead_view_catcher_started_on = Time.now
    $dead_view_catcher_nb_render = 0
    $dead_view_catcher_views = build_views_hash
    $dead_view_last_exception = nil

    watch_signal!(options)
    watch_all_instances_signal!(options) if !options[:grep].blank?

    ActionView::Template.send :include, DeadViewCatcher::Extensions::ActionView    
  end
  
  # Building the views hash (Only using app/views folders)
  def self.build_views_hash
    views = ActiveSupport::OrderedHash.new

    Dir.glob(File.join(Rails.root, 'app', 'views', '**', '*')).each do |v|
      if File.stat(v).file? 
        views[v.gsub(Rails.root, '').gsub(/^\//, '')] = 0
      end
    end
    
    return views
  end
  
  def self.watch_signal!(options)
    Signal.trap(options[:signal]) do
      begin
        puts ">> Dumping dead views..."
        open(File.join(Rails.root, options[:file]), 'w+') do |fd|
          fd.write(dump_hash($dead_view_catcher_views).to_yaml)
        end
      puts ">> Dead views dumped to #{options[:file]}"
      rescue Exception => e
        puts e.to_s + "\n" + e.backtrace.join("\n")
      end
    end
  end
  
  def self.watch_all_instances_signal!(options)
    Signal.trap(options[:all_instances_signal]) do
      begin
        puts ">> Starting gathering consolidated dead views..."
        # Getting all process pids :
        ps = `ps aux | grep -i "#{options[:grep]}"`.split("\n").select { |l| !l.index('grep') } 
        pids = ps.collect { |l| (l.split(/ +/, 2)[1].to_i rescue nil) }.compact - [Process.pid]

        last_pid = Process.pid
        total_hash = dump_hash
        total_hash[:pids] = [last_pid]
        total_hash[:nb_instances] = 1

        pids.each do |p|
          # Sending the signal to other instances
          `kill -s #{options[:signal]} #{p}`
        
          # Now waiting for the output
          i = 0; l = nil
          while (!(l = YAML.load_file(options[:file]) rescue nil) or l[:pid] != p) and i < 15
            sleep 0.1
            i += 1
          end
          
          if l and l[:pid] and l[:pid] != last_pid
            puts "  >> Agregating data from pid #{l[:pid]}"

            # Agregating datas...
            total_hash[:running_hours] += l[:running_hours]
            total_hash[:views_rendered] += l[:views_rendered]
            total_hash[:exception_caught] += l[:exception_caught]
            total_hash[:pids] << l[:pid]
            total_hash[:nb_instances] = total_hash[:pids].size
            l[:complete_stats].each do |k, v|
              total_hash[:complete_stats][k] += v
            end

            last_pid = l[:pid]
          else
            puts "  >> pid #{l[:pid]} skiped.."
          end
        end

        total_hash[:dead_views] = dead_views(total_hash[:complete_stats])

        open(File.join(Rails.root, options[:file]), 'w+') do |fd|
          fd.write(total_hash.to_yaml)
        end
        puts ">> Consolidated Dead views dumped to #{options[:file]}"
      rescue Exception => e
        puts e.to_s + "\n" + e.backtrace.join("\n")
      end
    end
  end
  
  def self.dead_views(h = nil)
    h ||= $dead_view_catcher_views
    deads = ActiveSupport::OrderedHash.new
    h.keys.sort.each do |k|
      if h[k] == 0
        deads[k] = h[k]
      end
    end
    deads
  end
  
  def self.dump_hash(dead_views_hash = nil)
    dump = ActiveSupport::OrderedHash.new
    
    dump[:running_hours] = ((Time.now - $dead_view_catcher_started_on) / 3600).round(2)
    dump[:views_rendered] = $dead_view_catcher_nb_render
    dump[:time] = Time.now
    dump[:pid] = Process.pid
    dump[:exception_caught] = [$dead_view_last_exception].compact
    dump[:dead_views] = dead_views(dead_views_hash)
    dump[:complete_stats] = $dead_view_catcher_views
    dump
  end
  
  module Extensions
    module ActionView

      def self.included(mod)
        mod.send :alias_method, :dead_view_catcher_render, :render
        mod.send :define_method, :render do |*opts|
          view_catcher_rendered
          dead_view_catcher_render(*opts)
        end
      end

      def view_catcher_rendered
        begin
          rp = relative_path
          if rp and rp.index('app/views') == 0
            $dead_view_catcher_nb_render += 1
            #Rails.logger.info "Rendering and counting: #{rp}"
            begin
              $dead_view_catcher_views[rp] += 1
            rescue
              raise "Index: #{rp} doesn't exist in dead_view_catcher_views Hash"
            end
          end
        rescue Exception => e
          $dead_view_last_exception = e.to_s + "\n" + e.backtrace.join("\n")
        end
      end

    end
  end
end