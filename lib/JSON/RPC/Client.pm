class JSON::RPC::Client;

# available at https://github.com/moritz/json
# or included in Rakudo * distributions
use JSON::Tiny;

use HTTP::Response::Grammar;

has Str $.url is rw;
has Array $.json_methods is rw;

submethod BUILD ( Str $url, Array $json_methods = [] ) {
    $.url = $url;

    # this is workaround for not yet implemented CANDO in Rakudo
    for $json_methods.values -> $json_method {
        my $role = RoleHOW.new;
        my $method = method ( Array *@json_params ) {
            return self!request(
                json_method => $json_method,
                json_params => [ @json_params ],
            );
        };
        $role.^add_method( $json_method, $method );
        $role.^compose( );
        self does $role;
    }
}

method !request( Str $json_method, Array $json_params = [ ] ) {
    my $json_id = ( 'a' .. 'z', 'A' .. 'Z', 0 .. 9 ).roll( 32 ).join;

    my $request = {
        'method' => $json_method,
        'params' => $json_params,
        'id'     => $json_id,
    };
    my $json_request = to-json( $request );

    my $http_request = "POST / HTTP/1.1\r\n";
    $http_request ~= sprintf "Host: %s\r\n", $.url;
    $http_request ~= sprintf "Content-Length: %d\r\n", $json_request.bytes;
    $http_request ~= "Content-Type: application/json\r\n";
    $http_request ~= "\r\n";
    $http_request ~= $json_request;

    my $socket = IO::Socket::INET.new;
    $socket.open( $.url, 80 );
    $socket.send( $http_request );
    my $http_response = $socket.recv( );
    $socket.close( );

    HTTP::Response::Grammar.parse($http_response);

    unless $/{'status'}{'code'} ~ 200 {
        # TODO replace with HTTP exception
        die $/{'status'}{'message'};
    }

    my $json_response = $/{'content'};
    my $response = from-json( $json_response );
    # TODO decoding exception

    if $response{'error'} {
        # TODO replace with JSON-RPC exception
        die $response{'error'};
    }

    if $response{'id'} !~~ $json_id {
        # TODO replace with JSON-RPC exception
        die 'Response id <> request id';
    }

    return $response{'result'};
}
