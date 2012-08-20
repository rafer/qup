require "spec_helper"
require "tmpdir"
require "timeout"

module Qup
  describe Drainer do
    class Client
      include Qup::DrainerAPI

      def process(message)
        messages << message.data
      end

      def messages
        @messages ||= []
      end
    end

    describe "#run" do
      let(:queue_uri) { "maildir://#{Dir.mktmpdir}" }
      let(:queue_name) { "test" }
      let(:queue) { Session.new(queue_uri).queue(queue_name) }

      it "doesn't blow up if #setup or #teardown is not defined" do
        queue.producer.produce("A")

        empty_client = Class.new do
          include Qup::DrainerAPI

          def process(*)
          end
        end

        drainer = Drainer.new({
          :max_size => 1,
          :client => empty_client.new,
          :queue_uri => queue_uri,
          :queue_name => queue_name
        })

        drainer.run
      end

      it "does blow up if #process isn't defined" do
        queue.producer.produce("A")

        empty_client = Class.new do
          include Qup::DrainerAPI
        end

        drainer = Drainer.new({
          :max_size => 1,
          :client => empty_client.new,
          :queue_uri => queue_uri,
          :queue_name => queue_name
        })

        expect { drainer.run }.to raise_error(NotImplementedError)
      end

      it "calls process until max_size is met" do
        ["A", "B", "C"].each { |d| queue.producer.produce(d) }

        client  = Client.new
        drainer = Drainer.new({
          :client => client,
          :max_size => 2,
          :queue_uri => queue_uri,
          :queue_name => queue_name
        })

        drainer.run
        client.messages.should == ["A", "B"]
      end

      it "returns when max_age is met" do
        client = Client.new
        drainer = Drainer.new({
          :client => client,
          :max_size => 1,
          :max_age => 0.001,
          :queue_uri => queue_uri,
          :queue_name => queue_name
        })

        Timeout.timeout(1) { drainer.run } # Does not hang
      end

      it "returns when max_age and max_size are present and one of the values is met" do

        client = Client.new

        ["A", "B", "C"].each { |d| queue.producer.produce(d) }

        drainer = Drainer.new({
          :client => client,
          :max_size => 1,
          :max_age => 5,
          :queue_uri => queue_uri,
          :queue_name => queue_name
        })

        drainer.run
        client.messages.should == ["A"]

      end


      it "calls the #setup, #process and #teardown in the correct order" do
        queue.producer.produce("A")

        client = Client.new

        drainer = Drainer.new({
          :max_size => 1,
          :client => client,
          :queue_uri => queue_uri,
          :queue_name => queue_name
        })

        client.should_receive(:setup).once.ordered
        client.should_receive(:process).once.ordered
        client.should_receive(:teardown).once.ordered

        drainer.run
      end
    end
  end
end
