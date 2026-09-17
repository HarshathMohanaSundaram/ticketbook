# Base for every business operation that writes.
#
# Services return a Result instead of raising or returning booleans, so a caller
# can tell "the seats were taken" from "the trip has already departed" and render
# the right message, without rescuing exceptions for control flow.
class ApplicationService
  Result = Data.define(:success, :value, :error, :meta) do
    def success? = success
    def failure? = !success

    # Lets a controller write `result.error` and get :seats_taken
    def to_s = error.to_s
  end

  def self.call(...) = new(...).call

  private

  def success(value, **meta) = Result.new(success: true, value: value, error: nil, meta: meta)
  def failure(error, **meta) = Result.new(success: false, value: nil, error: error, meta: meta)
end
