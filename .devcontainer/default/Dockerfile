FROM swift:latest

RUN \
  #
  # Get package list
  apt-get update && \
  # 
  # Install required packages
  apt-get install -y \
    curl && \
  # Install swift-format
  mkdir /opt/swift-format && \
  curl -sL https://github.com/apple/swift-format/archive/refs/tags/509.0.0.tar.gz | \
    tar -xz --strip-components=1 -C /opt/swift-format && \
  swift build --package-path /opt/swift-format && \
  cp $(swift build --package-path /opt/swift-format --show-bin-path)/swift-format /usr/local/bin && \
  rm -rf /opt/swift-format
