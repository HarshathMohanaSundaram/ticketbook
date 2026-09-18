# The test environment uses :memory_store so caching behaviour can be asserted,
# but a cache that survives between examples makes them order-dependent.
RSpec.configure do |config|
  config.before { Rails.cache.clear }
end
