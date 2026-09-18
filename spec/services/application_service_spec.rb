require "rails_helper"

RSpec.describe ApplicationService, type: :service do
  describe ApplicationService::Result do
    describe "a success" do
      subject(:result) { described_class.new(success: true, value: :thing, error: nil, meta: {}) }

      it "reports success" do
        expect(result).to be_success
      end

      it "does not report failure" do
        expect(result).not_to be_failure
      end

      it "carries the value" do
        expect(result.value).to eq(:thing)
      end
    end

    describe "a failure" do
      subject(:result) { described_class.new(success: false, value: nil, error: :seats_taken, meta: { seat_numbers: %w[4A] }) }

      it "reports failure" do
        expect(result).to be_failure
      end

      it "names the error as a symbol, leaving wording to the caller" do
        expect(result.error).to eq(:seats_taken)
      end

      it "carries detail for the message" do
        expect(result.meta[:seat_numbers]).to eq(%w[4A])
      end
    end

    describe "immutability" do
      subject(:result) { described_class.new(success: true, value: 1, error: nil, meta: {}) }

      it "is frozen, so two threads cannot interfere through it" do
        expect(result).to be_frozen
      end

      it "refuses mutation" do
        expect { result.instance_variable_set(:@value, 2) }.to raise_error(FrozenError)
      end
    end
  end

  describe ".call" do
    let(:service_class) do
      Class.new(described_class) do
        def initialize(a, b:, &block)
          @args = { a: a, b: b, block: !block.nil? }
        end

        def call = success(@args)
      end
    end

    it "forwards positional arguments" do
      expect(service_class.call(1, b: 2).value[:a]).to eq(1)
    end

    it "forwards keyword arguments" do
      expect(service_class.call(1, b: 2).value[:b]).to eq(2)
    end

    it "forwards a block" do
      expect(service_class.call(1, b: 2) { :hi }.value[:block]).to be(true)
    end

    it "builds a fresh instance per call, so per-call state is never shared" do
      first = service_class.new(1, b: 2)
      second = service_class.new(3, b: 4)

      expect(first.call.value[:a]).not_to eq(second.call.value[:a])
    end
  end
end
