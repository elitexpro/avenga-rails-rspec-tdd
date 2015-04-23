require 'rails_helper'

RSpec.describe Subscription, :type => :model do

  context "db" do
    context "indexes" do
      it { should have_db_index(:email).unique(true) }
      it { should have_db_index(:confirmation_token).unique(true) }
    end

    context "columns" do
      it { should have_db_column(:email).of_type(:string).with_options(limit: 100, null: false) }
      it { should have_db_column(:confirmation_token).of_type(:string).with_options(limit: 100, null: false) }
      it { should have_db_column(:confirmed).of_type(:boolean).with_options(default: 'f', null: false) }
      it { should have_db_column(:start_on).of_type(:date) }
    end
  end
  
  context "attributes" do

    it "has email" do
      expect(Subscription.new(email: "x@y.z")).to have_attributes(email: "x@y.z")
    end

    it "has confirmed" do
      expect(Subscription.new(confirmed: true)).to have_attributes(confirmed: true)
    end

    it "has confirmation_token" do
      expect(Subscription.new(confirmation_token: "what-a-token")).to have_attributes(confirmation_token: "what-a-token")
    end

    context "start_on" do

      it "is an attribute" do
        today = Date.today
        expect(Subscription.new(start_on: Date.today)).to have_attributes(start_on: today)
      end

      it "defaults to today" do
        now = Time.zone.now
        today = now.to_date
        travel_to now do
          expect(Subscription.new.start_on).to eq(today)
        end
      end

    end

  end

  context "validation" do
    
    before do
      @subscription = Subscription.new(confirmation_token: "token", email: "a@b.c")
    end

    it "requires unique email" do
      expect(@subscription).to validate_uniqueness_of(:email)
    end

    it "requires email" do
      expect(@subscription).to validate_presence_of(:email)
    end

    it "requires confirmation_token" do
      expect(@subscription).to validate_presence_of(:confirmation_token)
    end

    it "requires unique confirmation_token" do
      expect(@subscription).to validate_uniqueness_of(:confirmation_token)
    end

    it "requires start_on" do
      expect(@subscription).to validate_presence_of(:start_on)
    end
  end

  context "scopes" do
    
    describe ".confirmation_overdue" do

      before do
        # Freeze time as confirmation_overdue scope is time-sensitive
        travel_to Time.zone.now
      end

      after { travel_back }
      
      it "returns unconfirmed subscriptions of age more than 3 days" do
        overdue = create(:subscription, confirmed: false, created_at: (3.days + 1.second).ago)
        expect(Subscription.confirmation_overdue).to match_array [overdue]
      end

      it "does not return unconfirmed subscriptions of age 3 days or younger" do
        create(:subscription, confirmed: false, created_at: 3.days.ago)
        expect(Subscription.confirmation_overdue).to be_empty
      end

      it "does not return confirmed subscriptions" do
        create(:subscription, confirmed: true, created_at: 1.year.ago)
        expect(Subscription.confirmation_overdue).to be_empty
      end

    end

  end

  describe "#to_param" do
    
    it "uses confirmation_token as the default identifier for routes" do
      subscription = Subscription.new(confirmation_token: "hello-im-a-token-123")
      expect(subscription.to_param).to eq("hello-im-a-token-123")
    end

  end

  describe ".create_and_request_confirmation(params)" do
    
    it "creates an unconfirmed subscription with the given params" do
      params = { email: "subscriber@somedomain.tld", start_on: "2015-01-31" }
      Subscription.create_and_request_confirmation(params)

      subscription = Subscription.first

      expect(subscription.confirmed?).to eq(false)
      expect(subscription.email).to eq(params[:email])
      expect(subscription.start_on).to eq(Date.new(2015, 1, 31))
    end

    it "saves subscription with a secure random confirmation_token" do
      expect(::SecureRandom).to receive(:hex).with(32).and_call_original
      subscription = Subscription.create_and_request_confirmation(email: "hello@example.tld")
      subscription.reload
      
      expect(subscription.confirmation_token).to match(/\A[a-z0-9]{64}\z/)
    end

    it "emails a confirmation request" do
      expect(SubscriptionMailer)
        .to receive(:send_confirmation_request!)
        .with(Subscription)
      
      Subscription.create_and_request_confirmation(email: "subscriber@somedomain.tld")
    end

    it "doesn't create subscription if emailing fails" do

      expect(SubscriptionMailer)
        .to receive(:send_confirmation_request!)
        .and_raise("Bad news, delivery failed!")

      email = "subscriber@somedomain.tld"
      expect do
        Subscription.create_and_request_confirmation(email: email)
      end.to raise_error "Bad news, delivery failed!"

      expect(Subscription.exists?).to eq(false)
    end

    it "raises an error if the subscription can't be created" do
      blank_email = ""
      expect do
        Subscription.create_and_request_confirmation(email: blank_email)
      end.to raise_error ActiveRecord::RecordInvalid
    end

    it "doesn't send an email if the subscription can't be created" do
      blank_email = ""
      expect do
        expect do 
          Subscription.create_and_request_confirmation(email: blank_email)
        end.to raise_error ActiveRecord::RecordInvalid
      end.not_to change { ActionMailer::Base.deliveries.size }
    end

    it "raises an error if the emailing fails" do
      expect(SubscriptionMailer)
        .to receive(:send_confirmation_request!)
        .and_raise("Bad news, delivery failed!")

      email = "subscriber@somedomain.tld"
      expect do
        Subscription.create_and_request_confirmation(email: email)
      end.to raise_error "Bad news, delivery failed!"
    end

  end

  describe ".confirm(confirmation_token)" do
    
    it "confirms the subscription matching the confirmation_token" do
      token = Subscription.generate_confirmation_token
      subscription = Subscription.create!(
        email: "a@a.a", 
        confirmation_token: token
      )
      expect(subscription.confirmed?).to eq(false)

      returned_subscription = Subscription.confirm(token)
      subscription.reload

      expect(subscription).to eq(returned_subscription)
      expect(subscription.confirmed?).to eq(true)
    end

    it "gracefully handles confirming an already confirmed subscription" do
      subscription = Subscription.create!(
        email: "a@a.a", 
        confirmation_token: "xyz"
      )
      expect(subscription.confirmed?).to eq(false)

      2.times { Subscription.confirm("xyz") }

      expect(subscription.reload.confirmed?).to eq(true)
    end

    it "raises ActiveRecord::RecordNotFound if confirmation_token is unknown" do
      expect do
        Subscription.confirm("unknown-token")
      end.to raise_error ActiveRecord::RecordNotFound
    end

  end

end
