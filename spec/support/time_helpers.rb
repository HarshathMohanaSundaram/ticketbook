RSpec.configure do |config|
  # The cancellation cutoff and the hold window are clock rules, so most service
  # specs need to stand at a particular moment.
  config.include ActiveSupport::Testing::TimeHelpers
end
