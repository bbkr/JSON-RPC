use JSON::Tiny;
use JSON::RPC::Error;
use HTTP::Easy::PSGI;

class JSON::RPC::Server;

# application to dispatch requests to
has Any $.application is rw = Any.new;

method run ( Str :$host = '', Int :$port = 8080, Bool :$debug = False ) {

    my $app = sub (%env) {
        
        # request can be Str, Buf or IO as described in
        # https://github.com/supernovus/perl6-http-easy/issues/3
        my $request;
        given %env{'psgi.input'} {
            when Str { $request = $_ }
            when Buf { $request = .decode }
            when IO { $request = .slurp }
        }
        
        # dispatch remote procedure call
        my $response = self.handler( json => $request );
        
        return [
            200, [
                'Content-Type' => 'application/json',
                'Content-Length' => $response.encode( 'UTF-8' ).bytes
            ], [ $response ]
        ];
    };

    my $psgi = HTTP::Easy::PSGI.new( :$host, :$port, :$debug );
    $psgi.app( $app );
    $psgi.run;
}

method handler ( Str :$json! ) {
    my $out;

    # Response object template
    my %template = (
        # A String specifying the version of the JSON-RPC protocol.
        # MUST be exactly "2.0".
        'jsonrpc' => '2.0',
    );

    try {
        my $parsed = self!parse_json( $json );

        my @requests;
        if $parsed ~~ Array {
            # To send several Request objects at the same time,
            # the Client MAY send an Array filled with Request objects.
            # INFO: empty Array is not valid request
            JSON::RPC::InvalidRequest.new.throw unless $parsed.elems;
            @requests = $parsed.list;
        }
        else {
            @requests.push( $parsed );
        }
        
        my @responses = gather for @requests -> $request {

            # Response object
            my %response;
            
            try {
                my $mode        = self!validate_request( $request );
                
                # When a rpc call is made, the Server MUST reply with a Response,
                # except for in the case of Notifications.
                unless $mode ~~ 'Notification' {
                    %response = %template;
                    
                    # This member is REQUIRED.
                    # It MUST be the same as the value of the id member in the Request Object.
                    %response{'id'} = $request{'id'};
                }
                
                my $method      = self!search_method( $request{'method'} );
                my $candidate   = self!validate_params( $method, $request{'params'} );
                my $result      = self!call( $candidate, $request{'params'} );
                
                # The Server MUST NOT reply to a Notification,
                # including those that are within a batch request.
                next if $mode ~~ 'Notification';

                # This member is REQUIRED on success.
                %response{'result'} = $result;

                CATCH {
                    when JSON::RPC::InvalidRequest {

                        %response = %template;

                        # This member is REQUIRED on error.
                        %response{'error'} = .Hash;

                        # This member is REQUIRED.
                        # If there was an error in detecting the id in the Request object, it MUST be Null.
                        %response{'id'} = Any;
                    }
                    when JSON::RPC::Error {

                        # Notifications are not confirmable by definition,
                        # since they do not have a Response object to be returned.
                        # As such, the Client would not be aware of any errors.
                        next if $mode ~~ 'Notification';

                        # This member is REQUIRED on error.
                        %response{'error'} = .Hash;
                    }
                }
            }

            take {%response};
        }

        return unless ?@responses;
        
        $out = $parsed ~~ Array ?? @responses !! @responses.pop;

        CATCH {

            # If the batch rpc call itself fails to be recognized as an valid JSON
            # or as an Array with at least one value,
            # the response from the Server MUST be a single Response object.
            when JSON::RPC::ParseError|JSON::RPC::InvalidRequest {

                # Response object
                $out = %template;
                
                # This member is REQUIRED on error.
                $out{'error'} = .Hash;

                # This member is REQUIRED.
                # If there was an error in detecting the id in the Request object, it MUST be Null.
                $out{'id'} = Any;
            }
        }
    };

    return to-json( $out );
}

method !parse_json ( Str $body ) {

    my $parsed;

    try { $parsed = from-json( $body ); };

    JSON::RPC::ParseError.new( data => ~$! ).throw if defined $!;
    JSON::RPC::ParseError.new.throw unless $parsed ~~ Array|Hash;

    return $parsed;
}

method !validate_request ( $request ) {
    my $mode;

    # A String specifying the version of the JSON-RPC protocol.
    # MUST be exactly "2.0".
    subset MemberJSONRPC where '2.0';

    # A String containing the name of the method to be invoked.
    # Method names that begin with the word rpc followed by a period character
    # are reserved for rpc-internal methods and extensions
    # and MUST NOT be used for anything else.
    subset MemberMethod where /^<!before rpc\.>/;

    # A Structured value that holds the parameter values to be used
    # during the invocation of the method. This member MAY be omitted.
    # (explained in "4.2 Parameter Structures")
    subset MemberParams where Array|Hash;

    # An identifier established by the Client that MUST contain
    # a String, Number, or NULL value if included.
    subset MemberID where Str|Int|Rat|Num|Any:U;

    given $request {
        when :( MemberJSONRPC :$jsonrpc!, MemberMethod :$method!, MemberID :$id! ) { $mode = 'Request' }
        when :( MemberJSONRPC :$jsonrpc!, MemberMethod :$method!, MemberParams :$params!, MemberID :$id! ) { $mode = 'Request' }
        when :( MemberJSONRPC :$jsonrpc!, MemberMethod :$method! ) { $mode = 'Notification' }
        when :( MemberJSONRPC :$jsonrpc!, MemberMethod :$method!, MemberParams :$params! ) { $mode = 'Notification' }
        default { JSON::RPC::InvalidRequest.new.throw; }
    }
    
    return $mode;
}

method !search_method ( Str $name ) {

    # locate public method in application
    my $method = $.application.^find_method( $name );

    JSON::RPC::MethodNotFound.new.throw unless $method;

    return $method;
}

method !validate_params ( Routine $method, $params is copy ) {

    # lack of "params" member is allowed
    # but Any is not flattenable
    $params //= [ ];

    # find all method candidates that recognize passed params
    my @candidates = $method.candidates_matching( self.application, |$params );

    JSON::RPC::InvalidParams.new.throw unless @candidates;

    # many mathches are not an error
    # first candidate is taken
    return @candidates.shift;
}

method !call ( Method $candidate, $params is copy ) {

    my $result;

    # lack of "params" member is allowed
    # but Any is not flattenable
    $params //= [ ];

    try {
        $result = $candidate.( self.application, |$params );

        CATCH {
            # wrap unhandled error type as internal error
            when not $_ ~~ JSON::RPC::Error {
                JSON::RPC::InternalError.new( data => .Str ).throw;
            }
        }
    };

    return $result;
}
