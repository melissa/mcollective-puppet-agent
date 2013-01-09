#!/usr/bin/env rspec

require 'spec_helper'

module MCollective
  class Application
    describe Puppet do
      before do
        application_file = File.join(File.dirname(__FILE__), '../../', 'application', 'puppet.rb')
        @app = MCollective::Test::ApplicationTest.new('puppet', :application_file => application_file).plugin

        client = mock
        client.stubs(:stats).returns(RPC::Stats.new)
        client.stubs(:progress=)
        @app.stubs(:client).returns(client)
        @app.stubs(:printrpc)
        @app.stubs(:printrpcstats)
        @app.stubs(:halt)
      end

      describe "#application_description" do
        it "should have a descrption set" do
          @app.should have_a_description
        end
      end

      describe "#post_option_parser" do
        it "should detect unsupported commands" do
          ARGV << "rspec"
          expect { @app.post_option_parser(@app.configuration) }.to raise_error(/Action must be/)
        end

        it "should get the concurrency for runall" do
          ARGV << "runall"
          ARGV << "1"

          @app.post_option_parser(@app.configuration)
          @app.configuration[:command].should == "runall"
          @app.configuration[:concurrency].should == 1
        end

        it "should get the message for disable" do
          ARGV << "disable"
          ARGV << "rspec test"

          @app.post_option_parser(@app.configuration)
          @app.configuration[:message].should == "rspec test"
        end

        it "should detect when no command is given" do
          ARGV.clear

          @app.expects(:raise_message).with(2)
          @app.post_option_parser(@app.configuration)
        end
      end

      describe "#validate_configuration" do
        it "should not allow the splay option when forcing" do
          @app.configuration[:force] = true
          @app.configuration[:splay] = true

          @app.expects(:raise_message).with(3)
          @app.validate_configuration(@app.configuration)
        end

        it "should not allow the splaylimit option when forcing" do
          @app.configuration[:force] = true
          @app.configuration[:splaylimit] = 60

          @app.expects(:raise_message).with(4)
          @app.validate_configuration(@app.configuration)
        end

        it "should ensure the runall command has a concurrency" do
          @app.configuration[:command] = "runall"

          @app.expects(:raise_message).with(5)
          @app.validate_configuration(@app.configuration)
        end
      end

      describe "#calculate_longest_hostname" do
        it "should calculate the correct size" do
          results = [{:sender => "a"}, {:sender => "abcdef"}, {:sender => "ab"}]
          @app.calculate_longest_hostname(results).should == 6
        end
      end

      describe "#display_results_single_field" do
        it "should print succesful results correctly" do
          result = [{:statuscode => 0, :sender => "rspec sender", :data => {:message => "rspec test"}}]
          @app.expects(:puts).with("   rspec sender: rspec test")
          @app.display_results_single_field(result, :message)
        end

        it "should print failed results correctly" do
          result = [{:statuscode => 1, :sender => "rspec sender", :data => {:message => "rspec test"}, :statusmsg => "error"}]
          Util.expects(:colorize).with(:red, "error").returns("error")
          @app.expects(:puts).with("   rspec sender: error")

          @app.display_results_single_field(result, :message)
        end

        it "should not fail for empty results" do
          @app.display_results_single_field([], :message).should == false
        end
      end

      describe "#summary_command" do
        it "should gather the summaries and display it" do
          @app.client.expects(:last_run_summary)
          @app.expects(:printrpcstats).with(:summarize => true)
          @app.expects(:halt)
          @app.summary_command
        end
      end

      describe "#status_command" do
        it "should display the :message result and stats" do
          @app.client.expects(:status).returns("rspec")
          @app.expects(:display_results_single_field).with("rspec", :message)
          @app.expects(:printrpcstats).with(:summarize => true)
          @app.expects(:halt)
          @app.status_command
        end
      end

      describe "#enable_command" do
        it "should enable the daemons and print results" do
          @app.client.expects(:enable)
          @app.expects(:printrpcstats).with(:summarize => true)
          @app.expects(:halt)
          @app.enable_command
        end
      end

      describe "#disable_command" do
        before do
          @app.expects(:printrpcstats).with(:summarize => true)
          @app.expects(:halt)
        end

        it "should support disabling with a message" do
          @app.configuration[:message] = "rspec test"
          @app.client.expects(:disable).with(:message => "rspec test").returns("rspec")
          @app.disable_command
        end

        it "should support disabling without a message" do
          @app.client.expects(:disable).with({}).returns("rspec")
          @app.disable_command
        end
      end

      describe "#runonce_command" do
        it "should run the agent along with any custom arguments" do
          @app.configuration[:force] = true
          @app.configuration[:server] = "rspec:123"
          @app.configuration[:noop] = true
          @app.configuration[:environment] = "rspec"
          @app.configuration[:splay] = true
          @app.configuration[:splaylimit] = 60
          @app.configuration[:tag] = ["one", "two"]

          @app.client.expects(:runonce).with(:force => true,
                                             :server => "rspec:123",
                                             :noop => true,
                                             :environment => "rspec",
                                             :splay => true,
                                             :splaylimit => 60,
                                             :tags => "one,two").returns("result")
          @app.expects(:halt)
          @app.runonce_command
        end
      end

      describe "#count_command" do
        it "should display the totals" do
          @app.client.expects(:status)
          @app.client.stats.expects(:okcount).returns(3)
          @app.client.stats.stubs(:failcount).returns(1)
          Util.expects(:colorize).with(:red, "Failed to retrieve status of 1 node").returns("Failed to retrieve status of 1 node")
          @app.expects(:extract_values_from_aggregates).returns(:enabled => {"enabled" => 3},
                                                                :applying => {true => 1, false => 2},
                                                                :daemon_present => {"running" => 2},
                                                                :idling => {true => 1})


          @app.expects(:puts).with("Total Puppet nodes: 3")
          @app.expects(:puts).with("          Nodes currently enabled: 3")
          @app.expects(:puts).with("         Nodes currently disabled: 0")
          @app.expects(:puts).with("Nodes currently doing puppet runs: 1")
          @app.expects(:puts).with("          Nodes currently stopped: 2")
          @app.expects(:puts).with("       Nodes with daemons started: 2")
          @app.expects(:puts).with("    Nodes without daemons started: 0")
          @app.expects(:puts).with("       Daemons started but idling: 1")
          @app.expects(:puts).with("Failed to retrieve status of 1 node")

          @app.count_command
        end
      end

      describe "#main" do
        it "should call the command if it exist" do
          @app.expects(:count_command)
          @app.configuration[:command] = "count"
          @app.main
        end

        it "should fail gracefully when a command does not exist" do
          @app.expects(:raise_message).with(6, "rspec")
          @app.configuration[:command] = "rspec"
          @app.main
        end
      end
    end
  end
end