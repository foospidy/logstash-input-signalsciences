# Instructions

This document aims to provide more detail on how to implement the logstash-input-signalsciences plugin.

## Installation

There are two methods of installing this plugin.

1. The plugin is published on rubygems.org (https://rubygems.org/gems/logstash-input-signalsciences) so it can be easily installed via Logstash by using the following command:

`logstash-plugin install logstash-input-signalciences`

2. You can build and install the gem file locally by using the `Makefile` locally on your system. However, you will need to ensure Ruby requirements for building gem files are met. Use the following commands:

`make build`

This command will build and install the gem file. You will need to ensure the `logstash-plugin` command is in your PATH.

## Configuration

Refer to the example configuration file [here](logstash-input-signalsciences.conf. This file assumes you will import the data into Elasticsearch using the logstash-output-elasticsearch plugin.

## Quick Start - Running the ELK stack locally
