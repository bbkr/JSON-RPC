BEGIN { @*INC.unshift('lib') }

use Test;
use JSON::Tiny;
use JSON::RPC::Client;

plan( 16 );

my ($rpc, $name);

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
    '{"jsonrpc": "2.0", "error": {"code": -32601, "message": "Method not found."}, "id": "1"}',
	ids => [ "1" ]
);
try { $rpc.foobar( ) };
isa_ok $!, JSON::RPC::MethodNotFound, $name;

spec(
    'rpc call with invalid JSON',
    '{"jsonrpc": "2.0", "method": "foobar, "params": "bar", "baz]',
    '{"jsonrpc": "2.0", "error": {"code": -32700, "message": "Parse error."}, "id": null}',
	force => True
);
try { $rpc.dummy( ) };
isa_ok $!, JSON::RPC::ParseError, $name;

spec(
    'rpc call with invalid Request object',
    '{"jsonrpc": "2.0", "method": 1, "params": "bar"}',
    '{"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid Request."}, "id": null}',
	force => True
);
try { $rpc.dummy( ) };
isa_ok $!, JSON::RPC::InvalidRequest, $name;

spec(
    'rpc call Batch, invalid JSON',
    '[
      {"jsonrpc": "2.0", "method": "sum", "params": [1,2,4], "id": "1"},
      {"jsonrpc": "2.0", "method"
    ]',
    '{"jsonrpc": "2.0", "error": {"code": -32700, "message": "Parse error."}, "id": null}',
	force => True
);
try {
	$rpc.'rpc.batch'( ).dummy( );
	$rpc.'rpc.flush'( );
};
isa_ok $!, JSON::RPC::ParseError, $name;

spec(
    'rpc call with an empty Array',
    '[]',
    '{"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid Request."}, "id": null}'
);
try { $rpc.'rpc.flush'( ) };
isa_ok $!, JSON::RPC::InvalidRequest, $name;

# spec(
#     'rpc call with an invalid Batch (but not empty)',
#     '[1]',
#     '[
#       {"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid Request."}, "id": null}
#     ]'
# );
# 
# spec(
#     'rpc call with invalid Batch',
#     '[1,2,3]',
#     '[
#       {"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid Request."}, "id": null},
#       {"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid Request."}, "id": null},
#       {"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid Request."}, "id": null}
#     ]'
# );
# 
# spec(
#     'rpc call Batch',
#     '[
#         {"jsonrpc": "2.0", "method": "sum", "params": [1,2,4], "id": "1"},
#         {"jsonrpc": "2.0", "method": "notify_hello", "params": [7]},
#         {"jsonrpc": "2.0", "method": "subtract", "params": [42,23], "id": "2"},
#         {"foo": "boo"},
#         {"jsonrpc": "2.0", "method": "foo.get", "params": {"name": "myself"}, "id": "5"},
#         {"jsonrpc": "2.0", "method": "get_data", "id": "9"} 
#     ]',
#     '[
#         {"jsonrpc": "2.0", "result": 7, "id": "1"},
#         {"jsonrpc": "2.0", "result": 19, "id": "2"},
#         {"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid Request."}, "id": null},
#         {"jsonrpc": "2.0", "error": {"code": -32601, "message": "Method not found."}, "id": "5"},
#         {"jsonrpc": "2.0", "result": ["hello", 5], "id": "9"}
#     ]'
# );

spec(
    'rpc call Batch (all notifications)',
    '[
        {"jsonrpc": "2.0", "method": "notify_sum", "params": [1,2,4]},
        {"jsonrpc": "2.0", "method": "notify_hello", "params": [7]}
    ]',
    Nil # Nothing is returned for all notification batches
);
is $rpc.'rpc.batch'( ).'rpc.notification'( ).notify_sum( 1, 2, 4 ), Nil, $name ~ ' stack';
is $rpc.'rpc.batch'( ).'rpc.notification'( ).notify_hello( 7 ), Nil, $name ~ ' stack';
is $rpc.'rpc.flush'(), Nil, $name ~ ' flush';

# Other tests not covered by specification examples

# dies_ok {
#     JSON::RPC::Client.new( url => 'http:///X##y' )
# }, 'cannot initialize using incorrect URL';
# 
# lives_ok {
#     JSON::RPC::Client.new( url => 'http://rakudo.org' )
# }, 'can initialize using correct URL';
# 
# lives_ok {
#     $rpc = JSON::RPC::Client.new( uri => URI.new('http://rakudo.org') )
# }, 'can initialize using URI object';
# 
# try { $rpc.ping( ) };
# isa_ok $!, JSON::RPC::TransportError, 'live test';

spec(
    'params member omitted when no params passed',
    '{"jsonrpc": "2.0", "method": "ping", "id": 1}',
    '{"jsonrpc": "2.0", "result": "pong", "id": 1}'
);
is $rpc.ping( ), 'pong', $name;

dies_ok { $rpc.subtract( 23, minuend => 42 ) },
    'cannot use positional and named params at the same time';


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

