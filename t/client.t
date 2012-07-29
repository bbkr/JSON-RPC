BEGIN { @*INC.unshift('lib') }

use Test;
use JSON::RPC::Client;

plan( 5 );

# construction
dies_ok { JSON::RPC::Client.new( url => 'http:///X##y' ) }, 'cannot initialize using incorrect URL';
lives_ok { JSON::RPC::Client.new( url => 'http://rakudo.org' ) }, 'can initialize using correct URL';
lives_ok { JSON::RPC::Client.new( uri => URI.new('http://rakudo.org') ) }, 'can initialize using URI object';

# since forks or threads are not yet implemented
# it is impossible to safely test Client against Server

my $rpc = JSON::RPC::Client.new( url => 'http://rakudo.org' );
isa_ok $rpc, JSON::RPC::Client;

# test JSON::RPC::Transport exception
{
    dies_ok {
        $rpc.ping( )
    }, 'call failed on not JSON content';
}

# more tests will follow
