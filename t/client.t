BEGIN { @*INC.unshift('lib') }

use Test;
use JSON::Tiny;
use JSON::RPC::Client;

plan( 9 );

my ($rpc, $case);

# mocked handler for transport layer -
# request produced by client is compared to request from specification exmaple
# and then response from specification exmaple is returned
sub transport ( Str :$json, Bool :$is_notification ) {
    my $got         = from-json( $json );
    my $expected    = from-json( $case[ 1 ] );
    my $returned    = from-json( $case[ 2 ] );
    
    # request produced by client
    # and request from specification example
    # must be of the same type
    die unless $got.WHAT === $expected.WHAT;
    
    # specification examples have fixed "id" members
    # while client generates random values for "id" members in request
    # so they have to be remapped in mocked transport response to avoid failure on mismatch
    my %ids;
    given $got {
        when Hash {
            %ids{ $expected.delete( 'id' ) } = $got.delete( 'id' ) if $got.exists( 'id' );
        }
    }
    given $returned {
        when Hash {
            $returned{'id'} = %ids{ $returned{'id'} } if defined $returned{'id'};
        }
    }

    # after id striping request produced by client
    # and request from specification exmaple must match deeply
    die unless $got eqv $expected;

    # convert response from specification example
    # with remapped "id" members back to JSON
    return to-json( $returned );
}

$rpc = JSON::RPC::Client.new( transport => &transport );

# Specification examples from L<http://www.jsonrpc.org/specification#examples>

$case = [
    'rpc call with positional parameters',
    '{"jsonrpc": "2.0", "method": "subtract", "params": [42, 23], "id": 1}',
    '{"jsonrpc": "2.0", "result": 19, "id": 1}',
];
is $rpc.subtract( 42, 23 ), 19, $case[0];

$case = [
    'rpc call with positional parameters',
    '{"jsonrpc": "2.0", "method": "subtract", "params": [23, 42], "id": 2}',
    '{"jsonrpc": "2.0", "result": -19, "id": 2}',
];
is $rpc.subtract( 23, 42 ), -19, $case[0];

$case = [
    'rpc call with named parameters',
    '{"jsonrpc": "2.0", "method": "subtract", "params": {"subtrahend": 23, "minuend": 42}, "id": 3}',
    '{"jsonrpc": "2.0", "result": 19, "id": 3}'
];
is $rpc.subtract( subtrahend => 23, minuend => 42 ), 19, $case[0];

$case = [
    'rpc call with named parameters',
    '{"jsonrpc": "2.0", "method": "subtract", "params": {"minuend": 42, "subtrahend": 23}, "id": 4}',
    '{"jsonrpc": "2.0", "result": 19, "id": 4}'
];
is $rpc.subtract( subtrahend => 23, minuend => 42 ), 19, $case[0];

# NYI notification tests

$case = [
    'rpc call of non-existent method',        
    '{"jsonrpc": "2.0", "method": "foobar", "id": "1"}',
    '{"jsonrpc": "2.0", "error": {"code": -32601, "message": "Method not found."}, "id": "1"}'
];
try { $rpc.foobar( ) };
isa_ok $!, JSON::RPC::MethodNotFound, $case[0];

# NYI remainig tests

# Other tests not covered by specification examples

dies_ok {
    JSON::RPC::Client.new( url => 'http:///X##y' )
}, 'cannot initialize using incorrect URL';

lives_ok {
    JSON::RPC::Client.new( url => 'http://rakudo.org' )
}, 'can initialize using correct URL';

lives_ok {
    $rpc = JSON::RPC::Client.new( uri => URI.new('http://rakudo.org') )
}, 'can initialize using URI object';

try { $rpc.ping( ) };
isa_ok $!, JSON::RPC::TransportError, 'live test';
