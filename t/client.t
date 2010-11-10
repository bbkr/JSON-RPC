BEGIN { @*INC.unshift('lib') }

use Test;
use JSON::RPC::Client;

my $c1 = JSON::RPC::Client.new(
    url             => 'api2.getresponse.com',
    json_methods    => ['ping', 'get_campaigns']
);

isa_ok $c1, JSON::RPC::Client;
ok $c1.can('ping'), 'method autoloaded';
ok $c1.can('get_campaigns'), 'method autoloaded';


my $c2 = JSON::RPC::Client.new(
    url             => 'api2.getresponse.com',
    json_methods    => []
);
isa_ok $c2, JSON::RPC::Client;
ok not $c2.can('ping'), 'autoloaded methods not visible outside instance';


# TODO tests, once Server is ready
#$c1.ping('SUPERSECRET').perl.say;
