require "database_cleaner/active_record"

RSpec.configure do |config|
  config.before(:suite) { DatabaseCleaner.clean_with(:truncation) }

  # A spec that spawns real threads declares `self.use_transactional_tests = false`
  # at the top of its group: each thread checks out its own connection and cannot
  # see another connection's open transaction, so the usual rollback-per-example
  # trick would hide the very rows the spec is trying to contend over.
  #
  # Those groups get truncated afterwards; everything else keeps the fast path.
  config.append_after(:each) do
    DatabaseCleaner.clean_with(:truncation) unless self.class.use_transactional_tests
  end
end
