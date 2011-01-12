Gem::Specification.new do |s|
  s.name = "dead_view_catcher"
  s.version = "0.1"
  s.author = "Guillaume Luccisano"
  s.email = "guillaume.luccisano@gmail.com"
  s.homepage = "http://github.com/kwi/dead_view_catcher"
  s.summary = "Find easily wich views you are not using anymore in your Rails app."
  s.description = "DeadViewCatcher is a gem for Ruby on Rails giving you an easy way to find which views you are not using anymore in your app. Might be really useful for big Rails app."

  s.files = Dir["{lib}/**/*", "[A-Z]*", "init.rb"]
  s.require_path = "lib"

  s.rubyforge_project = s.name
  s.required_rubygems_version = ">= 1.3.4"
end