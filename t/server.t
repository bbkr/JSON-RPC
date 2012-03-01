BEGIN { @*INC.unshift('lib') }

use Test;
use JSON::RPC::Server;

plan( 51 );

class CustomError does JSON::RPC::Error {
    method new {
        self.bless( *, code => -1, message => "GLaDOS", data => "The cake was a lie." );
    }
}

class Application {

    multi method echo { return }
    multi method echo ( Str $scream ) { return $scream }
    multi method echo ( Str :$scream ) { return $scream }

    method naughty ( Int :$age! where { $age >= 18 } ) { "You bad boy..." }

    multi method suicide ( Bool :$note! ) { die "The cake is a lie!" }
    multi method suicide { CustomError.new.throw }

    method !toothbrush { "No!" }
}

my $rpc = JSON::RPC::Server.new( application => Application, :debug );

isa_ok $rpc, JSON::RPC::Server;

# test JSON::RPC::ParseError exception
{
    lives_ok {
        $rpc.handler(
            json => '{'
        );
    }, 'parse error handled';
    ok !$rpc.history.{'result'}.defined, 'parse error has no result in response';
    ok !$rpc.history.{'id'}.defined, 'parse error has no id in response';
    is $rpc.history.{'error'}.{'code'}, -32700, 'parse error code matches spec';
    is $rpc.history.{'error'}.{'message'}, 'Parse error', 'parse error message matches spec';
    ok $rpc.history.{'error'}.{'data'} ~~ / final .* \} /, 'parse error data is propagated from parser';
}

# test JSON::RPC::InvalidRequest exception
{
    lives_ok {
        $rpc.handler(
            json => '{"foo":"bar"}'
        );
    }, 'invalid request handled';
    ok !$rpc.history.{'result'}.defined, 'invalid request has no result in response';
    ok !$rpc.history.{'id'}.defined, 'invalid request has no id in response';
    is $rpc.history.{'error'}.{'code'}, -32600, 'invalid request code matches spec';
    is $rpc.history.{'error'}.{'message'}, 'Invalid Request', 'invalid request message matches spec';
}

# test JSON::RPC::MethodNotFound exception
{
    # requested method does not exist
    lives_ok {
        $rpc.handler(
            json => '{"jsonrpc":"2.0","method":"foo","id":1}'
        );
    }, 'method not found handled';
    ok !$rpc.history.{'result'}.defined, 'method not found has no result in response';
    is $rpc.history.{'id'}, 1, 'method not found has matching id in response';
    is $rpc.history.{'error'}.{'code'}, -32601, 'method not found code matches spec';
    is $rpc.history.{'error'}.{'message'}, 'Method not found', 'method not found message matches spec';

    # requested method is private
    lives_ok {
        $rpc.handler(
            json => '{"jsonrpc":"2.0","method":"toothbrush","id":2}'
        );
    }, 'method not found handled';
    ok !$rpc.history.{'result'}.defined, 'method not found has no result in response';
    is $rpc.history.{'id'}, 2, 'method not found has matching id in response';
    is $rpc.history.{'error'}.{'code'}, -32601, 'method not found code matches spec';
    is $rpc.history.{'error'}.{'message'}, 'Method not found', 'method not found message matches spec';
}

# test JSON::RPC::InvalidParams exception
{
    lives_ok {
        $rpc.handler(
            json => '{"jsonrpc":"2.0","method":"naughty","params":{"age":10},"id":1}'
        );
    }, 'invalid params handled';
    ok !$rpc.history.{'result'}.defined, 'invalid params has no result in response';
    is $rpc.history.{'id'}, 1, 'invalid params has matching id in response';
    is $rpc.history.{'error'}.{'code'}, -32602, 'invalid params code matches spec';
    is $rpc.history.{'error'}.{'message'}, 'Invalid params', 'invalid params message matches spec';
}

# test valid calls
{
    # without params
    lives_ok {
        $rpc.handler(
            json => '{"jsonrpc":"2.0","method":"echo","id":1}'
        );
    }, 'valid call without params handled';
    ok !$rpc.history.{'error'}.defined, 'valid call has no error in response';
    is $rpc.history.{'id'}, 1, 'valid call has matching id in response';
    isa_ok $rpc.history.{'result'}, Any, 'valid call response';

    # with positional params
    lives_ok {
        $rpc.handler(
            json => '{"jsonrpc":"2.0","method":"echo","params":["3ch0"],"id":2}'
        );
    }, 'valid call with positional params handled';
    ok !$rpc.history.{'error'}.defined, 'valid call has no error in response';
    is $rpc.history.{'id'}, 2, 'valid call has matching id in response';
    is $rpc.history.{'result'}, '3ch0', 'valid call response';

    # with named params
    lives_ok {
        $rpc.handler(
            json => '{"jsonrpc":"2.0","method":"echo","params":{"scream":"3ch0"},"id":3}'
        );
    }, 'valid call with named params handled';
    ok !$rpc.history.{'error'}.defined, 'valid call has no error in response';
    is $rpc.history.{'id'}, 3, 'valid call has matching id in response';
    is $rpc.history.{'result'}, '3ch0', 'valid call response';
}

# test JSON::RPC::InternalError exception
{
    lives_ok {
        $rpc.handler(
            json => '{"jsonrpc":"2.0","method":"suicide","params":{"note":true},"id":1}'
        );
    }, 'internal error handled';
    ok !$rpc.history.{'result'}.defined, 'internal error has no result in response';
    is $rpc.history.{'id'}, 1, 'internal error has matching id in response';
    is $rpc.history.{'error'}.{'code'}, -32603, 'internal error code matches spec';
    is $rpc.history.{'error'}.{'message'}, 'Internal error', 'internal error message matches spec';
    is $rpc.history.{'error'}.{'data'}, 'The cake is a lie!', 'error data is propagated from aplication';
}

# test custom JSON::RPC::Error exception
{
    lives_ok {
        $rpc.handler(
            json => '{"jsonrpc":"2.0","method":"suicide","id":1}'
        );
    }, 'internal error handled';
    ok !$rpc.history.{'result'}.defined, 'internal error has no result in response';
    is $rpc.history.{'id'}, 1, 'internal error has matching id in response';
    is $rpc.history.{'error'}.{'code'}, -1, 'internal error code matches spec';
    is $rpc.history.{'error'}.{'message'}, 'GLaDOS', 'internal error message matches spec';
    is $rpc.history.{'error'}.{'data'}, 'The cake was a lie.', 'error data is propagated from aplication';
}
