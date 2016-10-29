require_relative "../test_helper"

class TestProxyDnsStaleCaching < Minitest::Test
  include ApiUmbrellaTests::Setup
  include ApiUmbrellaTests::Dns
  include Minitest::Hooks

  MAX_STALE = 3

  def setup
    setup_server
    once_per_class_setup do
      override_config_set({
        "dns_resolver" => {
          "nameservers" => ["[127.0.0.1]:#{$config["unbound"]["port"]}"],
          "max_stale" => MAX_STALE,
          "negative_ttl" => false,
        },
      }, "--router")
    end
  end

  def after_all
    super
    override_config_reset("--router")
  end

  def test_failed_host_down_after_ttl_expires
    ttl = 4
    set_dns_records(["stale-caching-down-after-ttl-expires.ooga #{ttl} A 127.0.0.1"])

    prepend_api_backends([
      {
        :frontend_host => "127.0.0.1",
        :backend_host => "stale-caching-down-after-ttl-expires.ooga",
        :servers => [{ :host => "stale-caching-down-after-ttl-expires.ooga", :port => 9444 }],
        :url_matches => [{ :frontend_prefix => "/#{unique_test_id}/stale-caching-down-after-ttl-expires/", :backend_prefix => "/info/" }],
      },
    ]) do
      wait_for_response("/#{unique_test_id}/stale-caching-down-after-ttl-expires/", {
        :code => 200,
        :local_interface_ip => "127.0.0.1",
      })

      set_dns_records([])
      start_time = Time.now
      wait_for_response("/#{unique_test_id}/stale-caching-down-after-ttl-expires/", {
        :code => 502,
      })
      duration = Time.now - start_time
      assert_operator(duration, :>=, (ttl - TTL_BUFFER + MAX_STALE))
      # Double the TTL buffer factor on this test, to account for further
      # fuzziness with the timings of the stale record too.
      assert_operator(duration, :<, (ttl + TTL_BUFFER * 2 + MAX_STALE))
    end
  end
end