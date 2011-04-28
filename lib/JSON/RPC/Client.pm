class JSON::RPC::Client;

# available at https://github.com/moritz/json
# or included in Rakudo * distributions
use JSON::Tiny;

# available at https://github.com/cosimo/perl6-lwp-simple
# or included in Rakudo * distributions
use LWP::Simple;

has Str $.host is rw;
has Array $.json_methods is rw;

submethod BUILD ( Str $host, Array $json_methods = [] ) {
    $.host = $host;

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

    # generate random id to identify remote procedure call and response
    my $json_id = ( 'a' .. 'z', 'A' .. 'Z', 0 .. 9 ).roll( 32 ).join;

    # attach information about content type
    my %headers = ( 'Content-Type' => 'application/json' );

    # build JSON-RPC top object
    my $request = {
        'method' => $json_method,
        'params' => $json_params,
        'id'     => $json_id,
    };
    my $content = to-json( $request );

    # call remote host
    my $http_response = LWP::Simple.get( $.host, %headers, $content );

    unless $http_response {
        # TODO replace with LWP::Simple exception
        # response code and status line would be awesome....
        die 'HTTP request failed';
    }

    my $response = from-json( $http_response );
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
