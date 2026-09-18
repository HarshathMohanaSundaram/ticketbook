require "rails_helper"

RSpec.describe TripSearchForm, type: :form do
  subject(:form) { described_class.new(params) }

  let!(:origin) { create(:city, slug: "bangalore") }
  let!(:destination) { create(:city, slug: "chennai") }
  let(:params) { { from: origin.slug, to: destination.slug, date: 2.days.from_now.to_date } }

  describe "type casting" do
    context "with values arriving as strings from a query string" do
      let(:params) { super().merge(date: "2026-09-20", min_price: "1000", min_rating: "4.5") }

      it "casts the date" do
        expect(form.date).to eq(Date.new(2026, 9, 20))
      end

      it "casts the price to an integer" do
        expect(form.min_price).to eq(1000)
      end

      it "casts the rating to a decimal, not a float" do
        expect(form.min_rating).to be_a(BigDecimal)
      end
    end

    context "with an unparseable date" do
      let(:params) { super().merge(date: "banana") }

      it "leaves the date blank rather than raising" do
        expect(form.date).to be_nil
      end
    end
  end

  describe "normalising input" do
    context "when a select is submitted empty" do
      let(:params) { super().merge(bus_type: "", berth_type: "  ") }

      it "treats an empty bus type as no filter" do
        expect(form.bus_type).to be_nil
      end

      it "treats whitespace as no filter" do
        expect(form.berth_type).to be_nil
      end
    end

    context "when the sort is not one we offer" do
      let(:params) { super().merge(sort: "'; DROP TABLE trips; --") }

      it "falls back to the default sort" do
        expect(form.sort).to eq("departure")
      end
    end

    context "when amenities include a code we do not know" do
      let(:params) { super().merge(amenities: %w[helicopter wifi ""]) }

      it "keeps only the known codes" do
        expect(form.amenities).to eq([ "wifi" ])
      end
    end

    context "when amenities are absent" do
      it "defaults to an empty list" do
        expect(form.amenities).to eq([])
      end
    end
  end

  describe "#attempted?" do
    context "when nothing has been entered" do
      let(:params) { {} }

      it "is false, so the page can invite a search rather than scold" do
        expect(form).not_to be_attempted
      end
    end

    context "when only one field has been entered" do
      let(:params) { { from: origin.slug } }

      it "is true" do
        expect(form).to be_attempted
      end
    end
  end

  describe "#searchable?" do
    context "with a complete, valid search" do
      it "is true" do
        expect(form).to be_searchable
      end
    end

    context "with nothing entered" do
      let(:params) { {} }

      it "is false" do
        expect(form).not_to be_searchable
      end
    end

    context "with a missing destination" do
      let(:params) { { from: origin.slug, date: 2.days.from_now.to_date } }

      it "is false" do
        expect(form).not_to be_searchable
      end
    end
  end

  describe "validations" do
    context "when the origin is not a city we serve" do
      let(:params) { super().merge(from: "atlantis") }

      it "is invalid" do
        expect(form).not_to be_valid
      end

      it "says which field is wrong" do
        form.valid?
        expect(form.errors[:from]).to include("is not a city we serve")
      end
    end

    context "when both ends are the same city" do
      let(:params) { super().merge(to: origin.slug) }

      it "is invalid" do
        expect(form).not_to be_valid
      end

      it "explains the problem" do
        form.valid?
        expect(form.errors[:to]).to include("must differ from the origin")
      end
    end

    context "when the date is in the past" do
      let(:params) { super().merge(date: Date.current - 1) }

      it "is invalid" do
        expect(form).not_to be_valid
      end
    end

    context "when the date is today" do
      let(:params) { super().merge(date: Date.current) }

      it "is valid, because buses still leave later today" do
        expect(form).to be_valid
      end
    end

    context "when the minimum price is above the maximum" do
      let(:params) { super().merge(min_price: 900, max_price: 100) }

      it "is invalid" do
        expect(form).not_to be_valid
      end

      it "points at the maximum" do
        form.valid?
        expect(form.errors[:max_price]).to include("must be at least the minimum price")
      end
    end
  end

  describe "#min_price_paise" do
    context "when a price is given in rupees" do
      let(:params) { super().merge(min_price: 1000) }

      it "converts to paise at the edge of the system" do
        expect(form.min_price_paise).to eq(100_000)
      end
    end

    context "when no price is given" do
      it "stays blank rather than becoming zero" do
        expect(form.min_price_paise).to be_nil
      end
    end
  end

  describe "#filters_applied?" do
    context "with only the route and date" do
      it "is false" do
        expect(form).not_to be_filters_applied
      end
    end

    context "with a bus type chosen" do
      let(:params) { super().merge(bus_type: "ac") }

      it "is true" do
        expect(form).to be_filters_applied
      end
    end
  end

  describe "#filter_count" do
    let(:params) { super().merge(bus_type: "ac", min_rating: 4.0, amenities: %w[wifi cctv]) }

    it "counts each filter and each amenity" do
      expect(form.filter_count).to eq(4)
    end
  end

  describe "#filter_attributes" do
    context "when the same amenities arrive in a different order" do
      let(:one) { described_class.new(params.merge(amenities: %w[wifi cctv])) }
      let(:other) { described_class.new(params.merge(amenities: %w[cctv wifi])) }

      it "produces the same attributes, so one cache entry serves both" do
        expect(one.filter_attributes).to eq(other.filter_attributes)
      end
    end

    context "when a filter is absent" do
      it "omits it rather than storing a nil" do
        expect(form.filter_attributes).not_to have_key(:bus_type)
      end
    end
  end

  describe "#to_params" do
    let(:params) { super().merge(bus_type: "ac", amenities: %w[wifi]) }

    it "round trips the search back into a shareable URL" do
      expect(form.to_params).to include(from: origin.slug, to: destination.slug, bus_type: "ac")
    end

    it "drops empty values" do
      expect(form.to_params).not_to have_key(:berth_type)
    end
  end

  describe "#reversed_params" do
    it "swaps the origin and the destination" do
      expect(form.reversed_params).to include(from: destination.slug, to: origin.slug)
    end
  end
end
