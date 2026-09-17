Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }

  # Housekeeping only. TripSeat#claimable? already treats an expired hold as free
  # inside the row lock, so availability is correct with or without this running.
  # Fifteen minutes is therefore plenty -- a per-minute sweep would be precision
  # theatre for a job that repairs display state.
  #
  # load_from_hash! rather than create: it also removes cron entries that are no
  # longer declared here, so the schedule in Redis always matches the schedule in
  # code. With `create`, a renamed job leaves its old entry running forever.
  config.on(:startup) do
    # Wipe first: load_from_hash! only prunes entries it owns, so a job renamed in
    # a previous deploy would otherwise keep running from Redis forever.
    Sidekiq::Cron::Job.destroy_all!

    Sidekiq::Cron::Job.load_from_hash!(
      "trip_management" => {
        "cron" => "*/15 * * * *",
        "class" => "TripManagementJob",
        "queue" => "critical",
        "description" => "Release expired holds and mark trips as departed"
      }
    )
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end
