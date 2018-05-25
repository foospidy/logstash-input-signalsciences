# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/inputs/signalsciences"

describe LogStash::Inputs::signalsciences do

  it_behaves_like "an interruptible input plugin" do
    let(:config) { { "interval" => 600 } }
  end

end
