BEGIN { @*INC.unshift('lib') }

use Test;
use JSON::RPC::Client;

plan( 7 );

# Autoloading tests

my $c1 = JSON::RPC::Client.new(
    host            => 'api2.getresponse.com',
    json_methods    => [ 'ping', 'get_campaigns' ]
);

isa_ok $c1, JSON::RPC::Client;
ok $c1.can( 'ping' ), 'method autoloaded';
ok $c1.can( 'get_campaigns' ), 'method autoloaded';


my $c2 = JSON::RPC::Client.new(
    host            => 'api2.getresponse.com',
    json_methods    => [ ]
);
isa_ok $c2, JSON::RPC::Client;
ok not $c2.can( 'ping' ), 'autoloaded methods not visible outside instance';

# Live tests that use JSON-RPC demo service located at:
# http://jsolait.net/services/test.jsonrpc

my $c3 = JSON::RPC::Client.new(
    host             => 'http://jsolait.net/services/test.jsonrpc',
    json_methods     => [ 'echo', 'no_such_method' ]
);
is $c3.echo( 'Hello from Perl6 !' ), 'Hello from Perl6 !', 'live test valid request response extracted';
try {
    $c3.no_such_method( );
    CATCH { ok $! ~~ / MethodNotFound /, 'live test invalid request json error extracted' }
};

done;