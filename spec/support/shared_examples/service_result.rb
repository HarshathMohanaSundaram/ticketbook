# Every service returns an ApplicationService::Result, so the same questions get
# asked of every failure path: did it fail, why, and did it leave the database
# alone? The last one matters most here -- `return` inside a transaction commits
# in Rails, so a refused operation can still have written something.
RSpec.shared_examples "a refused operation" do |error_symbol|
  it "returns a failure" do
    expect(result).to be_failure
  end

  it "fails with :#{error_symbol}" do
    expect(result.error).to eq(error_symbol)
  end
end

RSpec.shared_examples "an operation that writes nothing" do |model|
  it "creates no #{model.name.underscore.humanize.downcase}" do
    expect { result }.not_to change(model, :count)
  end
end

RSpec.shared_examples "a replayed operation" do
  it "returns a success" do
    expect(result).to be_success
  end

  it "marks the result as a replay" do
    expect(result.meta[:replay]).to be(true)
  end
end
