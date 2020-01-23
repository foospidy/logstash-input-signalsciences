VERSION?=0.0.0

build:
	gem build logstash-input-signalsciences \
	&& logstash-plugin install logstash-input-signalsciences-$(VERSION).gem

run:
	logstash -f logstash-input-signalsciences.conf

install:
	logstash-plugin install logstash-input-signalsciences

remove:
	logstash-plugin remove logstash-input-signalsciences

publish:
	gem push logstash-input-signalsciences-$(VERSION).gem

clean:
	rm logstash-input-signalsciences-*.gem
