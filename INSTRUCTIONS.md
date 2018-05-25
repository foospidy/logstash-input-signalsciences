# Instructions

This document aims to provide more detail on how to implement the logstash-input-signalsciences plugin.

## Installation

There are two methods of installing this plugin.

1. The plugin is published on rubygems.org (https://rubygems.org/gems/logstash-input-signalsciences) so it can be easily installed via Logstash by using the following command:

`logstash-plugin install logstash-input-signalsciences`

2. You can build and install the gem file locally by using the `Makefile` on your system. However, you will need to ensure Ruby requirements for building gem files are met. Use the following commands:

`make build`

This command will build and install the gem file. You will need to ensure the `logstash-plugin` command is in your PATH.

## Configuration

Refer to the example configuration file [here](logstash-input-signalsciences.conf). The example file contains comments to explain each configuration option. This file assumes you will import the data into Elasticsearch using the logstash-output-elasticsearch plugin. However, you can certainly use any output plugin you like.

## Quick Start - Running the ELK stack locally

This section is optional. If you want to run a local ELK stack to run or test this plugin with, below are 
basic instructions for installing ELK on Mac OS. These instructions use Homebrew to install all packages.
You can find lots of ELK documentation online, this section is just intended to be a helpful quick overivew/guide.
you can also refer to Elasticsearch's getting started page: https://www.elastic.co/start

1. The first requirement is Java 8, run:

```
brew update
brew tap caskroom/versions
brew cask install java8
```

Reference https://stackoverflow.com/questions/24342886/how-to-install-java-8-on-mac

2. Next install Elasticsearch, Logstash, and Kibana, run:

```
brew install elasticsearch
brew install logstash
brew install kibana
```

With brew you can start/stop these services by running:

```
brew services start elasticsearch
brew services start logstash
brew services start kibana

brew services stop elasticsearch
brew services stop logstash
brew services stop kibana
```

## Quick Start - Developing logstash plugins

This section references to help you get started with logstash plugin development.

1. The article [So, You Want to Make a Logstash Plugin...](https://dzone.com/articles/so-you-want-to-make-a-logstash-plugin) is a great first step. It outlines installing Ruby requirements and setting up the Ruby environment. With this setup you can start developing on the logstash-input-signalsciences plugin, or any other plugin.

If you want to create a new plugin, see:

1. Plugin generator https://www.elastic.co/guide/en/logstash/current/plugins-inputs-generator.html, usage: https://github.com/elastic/logstash/blob/master/docs/static/plugin-generator.asciidoc

2. Submitting your plugin to [RubyGems.org and the Logstash-plugin repository] (https://www.elastic.co/guide/en/logstash/current/submitting-plugin.html).