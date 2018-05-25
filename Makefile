build:
	gem build logstash-input-signalsciences \
	&& logstash-plugin install logstash-input-signalsciences-0.1.0.gem

run:
	logstash -f logstash-input-signalsciences.conf

install:
	logstash-plugin install logstash-input-signalsciences

remove:
	logstash-plugin remove logstash-input-signalsciences

clean:
	rm logstash-input-signalsciences-*.gem