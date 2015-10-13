# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "perfectsched"
  s.version = "0.7.15"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Sadayuki Furuhashi"]
  s.date = "2012-09-19"
  s.email = "frsyuki@gmail.com"
  s.executables = ["perfectsched"]
  s.extra_rdoc_files = [
    "ChangeLog",
    "README.rdoc"
  ]
  s.files = [
    "bin/perfectsched",
    "lib/perfectsched.rb",
    "lib/perfectsched/backend.rb",
    "lib/perfectsched/backend/null.rb",
    "lib/perfectsched/backend/rdb.rb",
    "lib/perfectsched/backend/simpledb.rb",
    "lib/perfectsched/command/perfectsched.rb",
    "lib/perfectsched/croncalc.rb",
    "lib/perfectsched/engine.rb",
    "lib/perfectsched/version.rb"
  ]
  s.homepage = "https://github.com/treasure-data/perfectsched"
  s.require_paths = ["lib"]
  s.rubygems_version = "1.8.23"
  s.summary = "Highly available distributed cron built on RDBMS or SimpleDB"
  s.test_files = ["test/backend_test.rb", "test/test_helper.rb"]

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<cron-spec>, ["<= 0.1.2", ">= 0.1.2"])
      s.add_runtime_dependency(%q<sequel>, [">= 3.48.0", "< 5.0.0"])
      s.add_runtime_dependency(%q<perfectqueue>, ["~> 0.7.0"])
      s.add_runtime_dependency(%q<tzinfo>, ["~> 1.2.2"])
    else
      s.add_dependency(%q<cron-spec>, ["<= 0.1.2", ">= 0.1.2"])
      s.add_dependency(%q<sequel>, [">= 3.48.0", "< 5.0.0"])
      s.add_dependency(%q<perfectqueue>, ["~> 0.7.0"])
      s.add_dependency(%q<tzinfo>, ["~> 1.2.2"])
    end
  else
    s.add_dependency(%q<cron-spec>, ["<= 0.1.2", ">= 0.1.2"])
    s.add_dependency(%q<sequel>, ["~> 3.48.0"])
    s.add_dependency(%q<perfectqueue>, ["~> 0.7.0"])
    s.add_dependency(%q<tzinfo>, ["~> 1.2.2"])
  end
end

