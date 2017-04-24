use JSON::Tiny;
use X::JSON::RPC;
use HTTP::Easy::PSGI;

unit class JSON::RPC::Server;

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
            default { $request = '' }
        }

        # dispatch remote procedure call
        my $response = self.handler( json => $request );

        # on empty response return HTTP 204 as adviced in
        # https://groups.google.com/forum/?fromgroups=#!topic/json-rpc/X7I2oxIOX8A
        return [ 204, [ ], [ ] ] unless $response;

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

    # SPEC: Response object
    my %template = (
        # SPEC: A String specifying the version of the JSON-RPC protocol.
        # MUST be exactly "2.0".
        'jsonrpc' => '2.0',
    );

    try {
        my $parsed = self!parse_json( $json );

        my @requests;
        if $parsed ~~ Array {
            # SPEC: To send several Request objects at the same time,
            # the Client MAY send an Array filled with Request objects.
            # (empty Array is not valid request)
            X::JSON::RPC::InvalidRequest.new.throw unless $parsed.elems;
            @requests = $parsed.list;
        }
        else {
            @requests.push( $parsed );
        }

        my @responses = gather for @requests -> $request {

            # SPEC: Response object
            my %response;

            try {
                my $mode = self!validate_request( $request );

                # SPEC: When a rpc call is made, the Server MUST reply with a Response,
                # except for in the case of Notifications.
                unless $mode ~~ 'Notification' {
                    %response = %template;

                    # SPEC: This member is REQUIRED.
                    # It MUST be the same as the value of the id member in the Request Object.
                    %response{'id'} = $request{'id'};
                }

                my $method = self!search_method( $request{'method'} );

                my $result;
                if $request{'params'}:exists {
                    my $candidate = self!validate_params( $method, self.application, |$request{'params'} );
                    $result = self!call( $candidate, self.application, |$request{'params'} );
                }
                else {
                    my $candidate = self!validate_params( $method, self.application );
                    $result = self!call( $candidate, self.application );
                }

                # SPEC: The Server MUST NOT reply to a Notification,
                # including those that are within a batch request.
                next if $mode ~~ 'Notification';

                # SPEC: This member is REQUIRED on success.
                %response{'result'} = $result;

                CATCH {
                    when X::JSON::RPC::InvalidRequest {

                        %response = %template;

                        # SPEC: This member is REQUIRED on error.
                        %response{'error'} = .Hash;

                        # SPEC: This member is REQUIRED.
                        # If there was an error in detecting the id in the Request object, it MUST be Null.
                        %response{'id'} = Any;
                    }
                    when X::JSON::RPC {

                        # SPEC: Notifications are not confirmable by definition,
                        # since they do not have a Response object to be returned.
                        # As such, the Client would not be aware of any errors.
                        next if $mode ~~ 'Notification';

                        # SPEC: This member is REQUIRED on error.
                        %response{'error'} = .Hash;
                    }
                }
            }

            take {%response};
        }

        return unless ?@responses;

        $out = $parsed ~~ Array ?? @responses !! @responses.pop;

        CATCH {

            # SPEC: If the batch rpc call itself fails to be recognized as an valid JSON
            # or as an Array with at least one value,
            # the response from the Server MUST be a single Response object.
            when X::JSON::RPC::ParseError|X::JSON::RPC::InvalidRequest {

                # SPEC: Response object
                $out = %template;

                # SPEC: This member is REQUIRED on error.
                $out{'error'} = .Hash;

                # SPEC: This member is REQUIRED.
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

    X::JSON::RPC::ParseError.new( data => ~$! ).throw if defined $!;
    X::JSON::RPC::ParseError.new.throw unless $parsed ~~ Array|Hash;

    return $parsed;
}

method !validate_request ( $request ) {
    my $mode;

    # SPEC: A String specifying the version of the JSON-RPC protocol.
    # MUST be exactly "2.0".
    subset MemberJSONRPC of Str where '2.0';

    # SPEC: A String containing the name of the method to be invoked.
    # Method names that begin with the word rpc followed by a period character
    # are reserved for rpc-internal methods and extensions
    # and MUST NOT be used for anything else.
    subset MemberMethod of Str where /^<!before rpc\.>/;

    # SPEC: A Structured value that holds the parameter values to be used
    # during the invocation of the method. This member MAY be omitted.
    # (explained in "4.2 Parameter Structures")
    subset MemberParams of Iterable where Array|Hash;

    # SPEC: An identifier established by the Client that MUST contain
    # a String, Number, or NULL value if included.
    subset MemberID where Str|Int|Rat|Num|Any:U;

    given $request {
        when :( MemberJSONRPC :$jsonrpc!, MemberMethod :$method!, MemberID :$id! ) {
            $mode = 'Request';
        }
        when :( MemberJSONRPC :$jsonrpc!, MemberMethod :$method!, MemberParams :$params!, MemberID :$id! ) {
            $mode = 'Request';
        }
        when :( MemberJSONRPC :$jsonrpc!, MemberMethod :$method! ) {
            $mode = 'Notification';
        }
        when :( MemberJSONRPC :$jsonrpc!, MemberMethod :$method!, MemberParams :$params! ) {
            $mode = 'Notification';
        }
        default {
            X::JSON::RPC::InvalidRequest.new.throw;
        }
    }

    return $mode;
}

method !search_method ( Str $name ) {

    # locate public method in application
    my $method = $.application.^find_method( $name );

    X::JSON::RPC::MethodNotFound.new.throw unless $method;

    return $method;
}

method !validate_params ( Routine $method, |params ) {

    # find all method candidates that recognize passed params
    my @candidates = $method.cando( params );

    X::JSON::RPC::InvalidParams.new.throw unless @candidates;

    # many mathches are not an error
    # first candidate is taken
    return @candidates.shift;
}

method !call ( Method $candidate, |params ) {

    my $result;

    try {
        $result = $candidate( |params );

        CATCH {

            # wrap unhandled error type as internal error
            when not $_ ~~ X::JSON::RPC {
                X::JSON::RPC::InternalError.new( data => .Str ).throw;
            }
        }
    };

    return $result;
}

=begin pod

=TITLE class JSON::RPC::Server

Server implementing JSON-RPC 2.0 protocol.

Please check online documentation at L<https://github.com/bbkr/jsonrpc>.

=end pod
