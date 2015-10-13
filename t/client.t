BEGIN { @*INC.unshift('lib') }

use Test;
use JSON::Tiny;
use JSON::RPC::Client;

plan( 39 );

my ($rpc, $name, @responses, $responses);

# Specification examples from L<http://www.jsonrpc.org/specification#examples>

spec(
    'rpc call with positional parameters',
    '{"jsonrpc": "2.0", "method": "subtract", "params": [42, 23], "id": 1}',
    '{"jsonrpc": "2.0", "result": 19, "id": 1}'
);
is $rpc.subtract( 42, 23 ), 19, $name;

spec(
    'rpc call with positional parameters',
    '{"jsonrpc": "2.0", "method": "subtract", "params": [23, 42], "id": 2}',
    '{"jsonrpc": "2.0", "result": -19, "id": 2}',
    ids => [ 2 ]
);
is $rpc.subtract( 23, 42 ), -19, $name;

spec(
    'rpc call with named parameters',
    '{"jsonrpc": "2.0", "method": "subtract", "params": {"subtrahend": 23, "minuend": 42}, "id": 3}',
    '{"jsonrpc": "2.0", "result": 19, "id": 3}',
    ids => [ 3 ]
);
is $rpc.subtract( subtrahend => 23, minuend => 42 ), 19, $name;

spec(
    'rpc call with named parameters',
    '{"jsonrpc": "2.0", "method": "subtract", "params": {"minuend": 42, "subtrahend": 23}, "id": 4}',
    '{"jsonrpc": "2.0", "result": 19, "id": 4}',
    ids => [ 4 ]
);
is $rpc.subtract( subtrahend => 23, minuend => 42 ), 19, $name;

spec(
    'a Notification',
    '{"jsonrpc": "2.0", "method": "update", "params": [1,2,3,4,5]}',
    Nil
);
is $rpc.'rpc.notification'( ).update( 1, 2, 3, 4, 5 ), Nil, $name;

spec(
    'a Notification',
    '{"jsonrpc": "2.0", "method": "foobar"}',
    Nil
);
is $rpc.'rpc.notification'( ).foobar( ), Nil, $name;

spec(
    'rpc call of non-existent method',        
    '{"jsonrpc": "2.0", "method": "foobar", "id": "1"}',
    '{"jsonrpc": "2.0", "error": {"code": -32601, "message": "Method not found"}, "id": "1"}',
    ids => [ '1' ]
);
try { $rpc.foobar( ) };
isa-ok $!, X::JSON::RPC::MethodNotFound, $name;

spec(
    'rpc call with invalid JSON',
    '{"jsonrpc": "2.0", "method": "foobar, "params": "bar", "baz]',
    '{"jsonrpc": "2.0", "error": {"code": -32700, "message": "Parse error"}, "id": null}',
    force => True
);
try { $rpc.dummy( ) };
isa-ok $!, X::JSON::RPC::ParseError, $name;

spec(
    'rpc call with invalid Request object',
    '{"jsonrpc": "2.0", "method": 1, "params": "bar"}',
    '{"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid Request"}, "id": null}',
    force => True
);
try { $rpc.dummy( ) };
isa-ok $!, X::JSON::RPC::InvalidRequest, $name;

spec(
    'rpc call Batch, invalid JSON',
    '[
      {"jsonrpc": "2.0", "method": "sum", "params": [1,2,4], "id": "1"},
      {"jsonrpc": "2.0", "method"
    ]',
    '{"jsonrpc": "2.0", "error": {"code": -32700, "message": "Parse error"}, "id": null}',
    force => True
);
try {
    $rpc.'rpc.batch'( ).dummy( );
    $rpc.'rpc.flush'( );
};
isa-ok $!, X::JSON::RPC::ParseError, $name;

spec(
    'rpc call with an empty Array',
    '[]',
    '{"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid Request"}, "id": null}'
);
try { $rpc.'rpc.flush'( ) };
isa-ok $!, X::JSON::RPC::InvalidRequest, $name;

spec(
    'rpc call with an invalid Batch (but not empty)',
    '[1]',
    '[
      {"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid Request"}, "id": null}
    ]',
    force => True
);
lives-ok {
    $rpc.'rpc.batch'( ).dummy( );
    @responses = $rpc.'rpc.flush'( );
}, $name;
try { ~@responses[ 0 ] };
isa-ok $!, X::JSON::RPC::InvalidRequest, $name ~ ' validate';

spec(
    'rpc call with invalid Batch',
    '[1,2,3]',
    '[
      {"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid Request"}, "id": null},
      {"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid Request"}, "id": null},
      {"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid Request"}, "id": null}
    ]',
    force => True
);
lives-ok {
    $rpc.'rpc.batch'( ).dummy( );
    $rpc.'rpc.batch'( ).dummy( );
    $rpc.'rpc.batch'( ).dummy( );
    @responses = $rpc.'rpc.flush'( );
}, $name;
try { ~@responses[ 0 ] };
isa-ok $!, X::JSON::RPC::InvalidRequest, $name ~ ' validate';
try { ~@responses[ 1 ] };
isa-ok $!, X::JSON::RPC::InvalidRequest, $name ~ ' validate';
try { ~@responses[ 2 ] };
isa-ok $!, X::JSON::RPC::InvalidRequest, $name ~ ' validate';

spec(
    'rpc call Batch',
    '[
        {"jsonrpc": "2.0", "method": "sum", "params": [1,2,4], "id": "1"},
        {"jsonrpc": "2.0", "method": "notify_hello", "params": [7]},
        {"jsonrpc": "2.0", "method": "subtract", "params": [42,23], "id": "2"},
        {"foo": "boo"},
        {"jsonrpc": "2.0", "method": "foo.get", "params": {"name": "myself"}, "id": "5"},
        {"jsonrpc": "2.0", "method": "get_data", "id": "9"} 
    ]',
    '[
        {"jsonrpc": "2.0", "result": 7, "id": "1"},
        {"jsonrpc": "2.0", "result": 19, "id": "2"},
        {"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid Request"}, "id": null},
        {"jsonrpc": "2.0", "error": {"code": -32601, "message": "Method not found"}, "id": "5"},
        {"jsonrpc": "2.0", "result": ["hello", 5], "id": "9"}
    ]',
    ids => [ '1', '2', Any:U, '5', '9' ], force => True
);
lives-ok {
    $rpc.'rpc.batch'( ).sum( 1, 2, 4 );
    $rpc.'rpc.batch'( ).'rpc.notification'( ).notify_hello( 7 );
    $rpc.'rpc.batch'( ).subtract( 42, 23 );
    $rpc.'rpc.batch'( ).dummy( );
    $rpc.'rpc.batch'( ).'foo.get'( name => 'myself' );
    $rpc.'rpc.batch'( ).get_data( );
    @responses = $rpc.'rpc.flush'( );
}, $name;
is @responses[ 0 ], 7, $name ~ ' validate';
is @responses[ 1 ], 19, $name ~ ' validate';
try { ~@responses[ 2 ] };
isa-ok $!, X::JSON::RPC::InvalidRequest, $name ~ ' validate';
try { ~@responses[ 3 ] };
isa-ok $!, X::JSON::RPC::MethodNotFound, $name ~ ' validate';
is-deeply @responses[ 4 ], [ 'hello', 5 ], $name ~ ' validate';

spec(
    'rpc call Batch (all notifications)',
    '[
        {"jsonrpc": "2.0", "method": "notify_sum", "params": [1,2,4]},
        {"jsonrpc": "2.0", "method": "notify_hello", "params": [7]}
    ]',
    Nil # Nothing is returned for all notification batches
);
lives-ok {
    $rpc.'rpc.batch'( ).'rpc.notification'( ).notify_sum( 1, 2, 4 );
    $rpc.'rpc.batch'( ).'rpc.notification'( ).notify_hello( 7 );
    $responses := $rpc.'rpc.flush'();
}, $name;
isa-ok $responses, Nil, $name ~ ' validate';

# Other tests not covered by specification examples

dies-ok {
    JSON::RPC::Client.new( url => 'http:///X##y' )
}, 'cannot initialize using incorrect URL';

lives-ok {
    JSON::RPC::Client.new( url => 'http://rakudo.org' )
}, 'can initialize using correct URL';

lives-ok {
    $rpc = JSON::RPC::Client.new( uri => URI.new('http://rakudo.org') )
}, 'can initialize using URI object';

spec(
    'params member omitted when no params passed',
    '{"jsonrpc": "2.0", "method": "ping", "id": 1}',
    '{"jsonrpc": "2.0", "result": "pong", "id": 1}'
);
is $rpc.ping( ), 'pong', $name;

spec(
    'null id is allowed',
    '{"jsonrpc": "2.0", "method": "ping", "id": null}',
    '{"jsonrpc": "2.0", "result": "pong", "id": null}',
    ids => [ Any ]
);
is $rpc.ping( ), 'pong', $name;

spec(
    'not ordered Batch',
    '[
        {"jsonrpc": "2.0", "method": "ping", "id": 1},
        {"jsonrpc": "2.0", "method": "pong", "id": 2}
    ]',
    '[
        {"jsonrpc": "2.0", "result": "ping", "id": 2},
        {"jsonrpc": "2.0", "result": "pong", "id": 1}
    ]'
);
lives-ok {
    $rpc.'rpc.batch'( ).ping( );
    $rpc.'rpc.batch'( ).pong( );
    @responses = $rpc.'rpc.flush'( );
}, $name;
is @responses[ 0 ], 'pong', $name ~ ' validate';
is @responses[ 1 ], 'ping', $name ~ ' validate';

spec(
    'duplicated id in Batch',
    '[
        {"jsonrpc": "2.0", "method": "ping", "id": 1},
        {"jsonrpc": "2.0", "method": "pong", "id": 1}
    ]',
    '[
        {"jsonrpc": "2.0", "result": "pong", "id": 1},
        {"jsonrpc": "2.0", "result": "ping", "id": 1}
    ]',
    ids => [ 1, 1 ]
);
lives-ok {
    $rpc.'rpc.batch'( ).ping( );
    $rpc.'rpc.batch'( ).pong( );
    @responses = $rpc.'rpc.flush'( );
}, $name;
is @responses[ 0 ], 'pong', $name ~ ' validate';
is @responses[ 1 ], 'ping', $name ~ ' validate';

spec(
    'amount of Responses in Batch different than expected',
    '[
        {"jsonrpc": "2.0", "method": "ping", "id": 1},
        {"jsonrpc": "2.0", "method": "pong", "id": 2}
    ]',
    '[
        {"jsonrpc": "2.0", "result": "pong", "id": 1},
        {"jsonrpc": "2.0", "result": "ping", "id": 2},
        {"jsonrpc": "2.0", "result": "pang", "id": 3}
    ]',
    ids => [ 1, 2, 3 ]
);
try {
    $rpc.'rpc.batch'( ).ping( );
    $rpc.'rpc.batch'( ).pong( );
    $rpc.'rpc.flush'( )
};
isa-ok $!, X::JSON::RPC::ProtocolError, $name ~ ' validate';

try { $rpc.subtract( 23, minuend => 42 ) };
isa-ok $!, X::JSON::RPC::ProtocolError, 'cannot use positional and named params at the same time';

spec(
    'can invoke language built-in method name',
    '{"jsonrpc": "2.0", "method": "can", "params" : ["tuna"], "id": 1}',
    '{"jsonrpc": "2.0", "result": "meow", "id": 1}',
    ids => [ 1, 2, 3 ]
);
is $rpc.'rpc.can'( 'tuna' ), 'meow', $name;

# mocked handlers for transport layer

# request produced by client is compared to request from specification exmaple
# and then response from specification example is returned
sub transport ( Str :$json, Bool :$get_response, :$data_sent_to_Server, :$data_sent_to_Client, :$force ) {

    # sometimes request produced by client cannot mimic request from specification exmaple
    # this may happen when parse error or invalid Request is expected
    # in this case dummy call is ignored and response from specification example is returned
    return $data_sent_to_Client if $force;

    # request produced by client
    # and request from specification example must match deeply
    die unless from-json( $json ) eqv from-json( $data_sent_to_Server );

    return $data_sent_to_Client;
}

# mocked sequencer

sub sequencer ( :@ids ) {

    return @ids.shift;
}

sub spec ( $description, $data_sent_to_Server, $data_sent_to_Client, :$force = False, :@ids = [ 1 .. * ] ) {

    $name = $description;
    $rpc = JSON::RPC::Client.new(
        transport => &transport.assuming( :$data_sent_to_Server, :$data_sent_to_Client, :$force ),
        sequencer => &sequencer.assuming( :@ids )
    );
}
