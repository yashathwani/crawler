# frozen_string_literal: true

RSpec.describe(Crawler::HttpClient::FilteringDnsResolver) do
  let(:loopback_allowed) { false }
  let(:private_networks_allowed) { false }

  subject(:resolver) do
    described_class.new(
      :loopback_allowed => loopback_allowed,
      :private_networks_allowed => private_networks_allowed,
      :logger => Logger.new(STDOUT)
    )
  end

  context 'when private_networks_allowed=false' do
    it 'does not allow resolution of private IP addresses' do
      expect { resolver.resolve('monitoring.swiftype.net') }.to raise_error(Crawler::HttpClient::InvalidHost)
      expect { resolver.resolve('10.10.1.42') }.to raise_error(Crawler::HttpClient::InvalidHost)
    end

    it 'strips out private addresses, but allows the request if there is at least one public IP available' do
      expect(resolver.default_resolver).to receive(:resolve).and_return(
        [
          Java::JavaNet::InetAddress.get_by_name('swiftype.com'),
          Java::JavaNet::InetAddress.get_by_name('10.10.1.42')
        ]
      )
      expect(resolver.resolve('swiftype.com').map(&:host_name)).to contain_exactly('swiftype.com')
    end
  end

  context 'when private_networks_allowed=true' do
    let(:private_networks_allowed) { true }

    it 'allows resolution of private IP addresses' do
      expect(resolver.resolve('monitoring.swiftype.net').size).to eq(1)
      expect(resolver.resolve('10.10.1.42').size).to eq(1)
    end
  end

  it 'allows resolution of public IP addresses' do
    expect(resolver.resolve('swiftype.com').size).to eq(1)
    expect(resolver.resolve('173.192.91.158').size).to eq(1)
  end

  context 'for loopback IPs' do
    before do
      expect(resolver.default_resolver).to receive(:resolve).and_return(
        [Java::JavaNet::InetAddress.get_loopback_address]
      )
    end

    context 'when loopback_allowed=false' do
      it 'does not allow resolution of localhost' do
        expect { resolver.resolve('localhost:9292') }.to raise_error(Crawler::HttpClient::InvalidHost)
      end
    end

    context 'when loopback_allowed=true' do
      let(:loopback_allowed) { true }

      it 'allows resolution of localhost' do
        expect(resolver.resolve('localhost:9292').map(&:host_name)).to contain_exactly('localhost')
      end
    end
  end
end