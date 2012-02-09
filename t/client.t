BEGIN { @*INC.unshift('lib') }

use Test;
use JSON::RPC::Client;

plan( 2 );

my $rpc = JSON::RPC::Client.new( url => 'http://rakudo.org' );

isa_ok $rpc, JSON::RPC::Client;


# since forks or threads are not yet implemented
# it is impossible to safely test Client against Server

# however "need is the mother of all creation" and so
# live environment can be faked by calling raw json files on GitHub
# and pretend those are remote procedure responses :)


# test JSON::RPC::Transport exception
{
    dies_ok {
        $rpc.ping( )
    }, 'call failed on not JSON content';
}

# ... more tests soon ...