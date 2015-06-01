BEGIN { @*INC.unshift( 'lib' ) }

use Test;
use JSON::Tiny;
use JSON::RPC::Server;

plan( 29 );

class CustomError does X::JSON::RPC {
    method new {
        self.bless( code => -1, message => 'GLaDOS is watching', data => 'The cake was a lie.' );
    }
}

class Application {

    # methods used by specification examples
    multi method subtract ( $minuend!, $subtrahend! ) { return $minuend - $subtrahend }
    multi method subtract ( :$minuend!, :$subtrahend! ) { return $minuend - $subtrahend }
    method sum ( *@items ) { return [+]( @items ) }
    method notify_hello ( $count ){ $.count = $count }
    method get_data { return [ 'hello', 5 ] }

    # methods for own tests
    has Int $.count is rw;
    method void { return }
    multi method suicide ( Bool :$note! ) { die 'The cake is a lie!' }
    multi method suicide { CustomError.new.throw }
    method !toothbrush { "No!" }
    method rpc { return True }
    method can ( $fish ) { return 'meow' }
}

my $rpc = JSON::RPC::Server.new( application => Application.new );

isa-ok $rpc, JSON::RPC::Server;

# Specification examples from L<http://www.jsonrpc.org/specification#examples>

spec(
    'rpc call with positional parameters',
    '{"jsonrpc": "2.0", "method": "subtract", "params": [42, 23], "id": 1}',
    '{"jsonrpc": "2.0", "result": 19, "id": 1}',
);

spec(
    'rpc call with positional parameters',
    '{"jsonrpc": "2.0", "method": "subtract", "params": [23, 42], "id": 2}',
    '{"jsonrpc": "2.0", "result": -19, "id": 2}',
);

spec(
    'rpc call with named parameters',
    '{"jsonrpc": "2.0", "method": "subtract", "params": {"subtrahend": 23, "minuend": 42}, "id": 3}',
    '{"jsonrpc": "2.0", "result": 19, "id": 3}'
);

spec(
    'rpc call with named parameters',
    '{"jsonrpc": "2.0", "method": "subtract", "params": {"minuend": 42, "subtrahend": 23}, "id": 4}',
    '{"jsonrpc": "2.0", "result": 19, "id": 4}'
);

spec(
    'a Notification',
    '{"jsonrpc": "2.0", "method": "update", "params": [1,2,3,4,5]}',
    Nil
);

spec(
    'a Notification',
    '{"jsonrpc": "2.0", "method": "foobar"}',
    Nil
);

spec(
    'rpc call of non-existent method',        
    '{"jsonrpc": "2.0", "method": "foobar", "id": "1"}',
    '{"jsonrpc": "2.0", "error": {"code": -32601, "message": "Method not found"}, "id": "1"}'
);

spec(
    'rpc call with invalid JSON',
    '{"jsonrpc": "2.0", "method": "foobar, "params": "bar", "baz]',
    '{"jsonrpc": "2.0", "error": {"code": -32700, "message": "Parse error"}, "id": null}'
);

spec(
    'rpc call with invalid Request object',
    '{"jsonrpc": "2.0", "method": 1, "params": "bar"}',
    '{"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid Request"}, "id": null}'
);

spec(
    'rpc call Batch, invalid JSON',
    '[
      {"jsonrpc": "2.0", "method": "sum", "params": [1,2,4], "id": "1"},
      {"jsonrpc": "2.0", "method"
    ]',
    '{"jsonrpc": "2.0", "error": {"code": -32700, "message": "Parse error"}, "id": null}'
);

spec(
    'rpc call with an empty Array',
    '[]',
    '{"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid Request"}, "id": null}'
);

spec(
    'rpc call with an invalid Batch (but not empty)',
    '[1]',
    '[
      {"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid Request"}, "id": null}
    ]'
);

spec(
    'rpc call with invalid Batch',
    '[1,2,3]',
    '[
      {"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid Request"}, "id": null},
      {"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid Request"}, "id": null},
      {"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid Request"}, "id": null}
    ]'
);

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
    ]'
);

spec(
    'rpc call Batch (all notifications)',
    '[
        {"jsonrpc": "2.0", "method": "notify_sum", "params": [1,2,4]},
        {"jsonrpc": "2.0", "method": "notify_hello", "params": [7]}
    ]',
    Nil # Nothing is returned for all notification batches
);

# Other tests not covered by specification examples

spec(
    'no params and empty response',
    '{"jsonrpc": "2.0", "method": "void", "id": 1}',
    '{"jsonrpc": "2.0", "result": null, "id": 1}',
    cannonicalize => False
);

spec(
    'method named rpc can be called',
    '{"jsonrpc": "2.0", "method": "rpc", "id": 1}',
    '{"jsonrpc": "2.0", "result": true, "id": 1}',
    cannonicalize => False
);

spec(
    'parse error (empty string)',
    '',
    '{"jsonrpc": "2.0", "error": {"code": -32700, "message": "Parse error"}, "id": null}',
);

spec(
    'parse error (top container is not JSON Object or Array)',
    '42',
    '{"jsonrpc": "2.0", "error": {"code": -32700, "message": "Parse error"}, "id": null}',
);

spec(
    'invalid request (null is not the same as omitted params)',
    '{"jsonrpc": "2.0", "method": "void", "params": null, "id": 1}',
    '{"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid Request"}, "id": null}',
    cannonicalize => False
);

spec(
    'invalid params (no candidate found)',
    '{"jsonrpc": "2.0", "method": "void", "params": [1,2,3], "id": 1}',
    '{"jsonrpc": "2.0", "error": {"code": -32602, "message": "Invalid params"}, "id": 1}',
    cannonicalize => False
);

spec(
    'private method not found',
    '{"jsonrpc": "2.0", "method": "toothbrush", "id": 1}',
    '{"jsonrpc": "2.0", "error": {"code": -32601, "message": "Method not found"}, "id": 1}',
    cannonicalize => False
);

spec(
    'batch recursion forbidden',
    '[[{"jsonrpc": "2.0", "method": "void", "id": 1}]]',
    '[{"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid Request"}, "id": null}]',
    cannonicalize => False
);

spec(
    'null id does not mean notification (null is not the same as omitted id)',
    '{"jsonrpc": "2.0", "method": "void", "id": null}',
    '{"jsonrpc": "2.0", "result": null, "id": null}',
    cannonicalize => False
);

spec(
    'internal error',
    '{"jsonrpc": "2.0", "method": "suicide", "params": {"note": true}, "id": 1}',
    '{"jsonrpc": "2.0", "error": {"code": -32603, "message": "Internal error", "data": "The cake is a lie!"}, "id": 1}',
    cannonicalize => False
);

spec(
    'custom error',
    '{"jsonrpc": "2.0", "method": "suicide", "id": 1}',
    '{"jsonrpc": "2.0", "error": {"code": -1, "message": "GLaDOS is watching", "data": "The cake was a lie."}, "id": 1}',
    cannonicalize => False
);

spec(
    'can invoke language built-in method name',
    '{"jsonrpc": "2.0", "method": "can", "params": ["tuna"], "id": 1}',
    '{"jsonrpc": "2.0", "result": "meow", "id": 1}',
    cannonicalize => False
);

is $rpc.application.count, 7, 'notification was processed';

sub spec ( $description, $data_sent_to_Server, $data_sent_to_Client, :$cannonicalize = True ) {

    my ($got, $expected) = map { .defined ?? from-json( $_ ) !! $_ },
        $rpc.handler( json => $data_sent_to_Server ), $data_sent_to_Client;

    # specification examples do not contain optional field "data" in "error" member
    # so it must be removed from all Response objects before comparison
    if $cannonicalize {
        given $got {
            when Array { for $got.list { $_{'error'}{'data'}:delete if $_{'error'}{'data'}.defined } }
            when Hash { $got{'error'}{'data'}:delete if $got{'error'}{'data'}.defined }
        }
    }

    is-deeply $got, $expected, $description;
}
