use URI;
use LWP::Simple;
use JSON::Tiny;
use X::JSON::RPC;

unit class JSON::RPC::Client;

has Code $!transport;
has Code $!sequencer;
has Bool $.is_batch = False;
has Bool $.is_notification = False;
has @!stack = ( );

BEGIN {

    # install method auto dispatch
    $?PACKAGE.HOW.add_fallback(
        $?PACKAGE,

        # must return True or False to indicate if it can handle the fallback
        -> $, $name { True },

        # should return the Code object to invoke
        -> $object, $name {
            # workaround to allow dispatch to methods inherited from Any( ) and Mu( )
            my $method = $name.subst(/^rpc\./, '');
            
            # placeholder variables cannot be passed-through
            # so dispatch has to be done manually depending on nature of passed params
            method ( *@positional, *%named ) {

                if @positional  and %named {
                    X::JSON::RPC::ProtocolError.new(
                        message => 'Cannot use positional and named params at the same time'
                    ).throw;
                }
                elsif @positional {
                    $object!handler( :$method, params => @positional );
                }
                elsif %named {
                    $object!handler( :$method, params => %named );
                }
                else {
                    $object!handler( :$method );
                }
            };

        }
    );

}

multi submethod BUILD ( URI :$uri!, Code :$sequencer? ) {

    $!transport = &transport.assuming( uri => $uri );
    $!sequencer = $sequencer // &sequencer;
}

multi submethod BUILD ( Str :$url!, Code :$sequencer? ) {

    $!transport = &transport.assuming( uri => URI.new( $url, :is_validating ) );
    $!sequencer = $sequencer // &sequencer;
}

multi submethod BUILD ( Code :$transport!, Code :$sequencer? ) {

    $!transport = $transport;
    $!sequencer = $sequencer // &sequencer;
}

# TODO: Replace it with HTTP::Client in the future
sub transport ( URI :$uri, Str :$json, Bool :$get_response ) {

    # HTTP protocol always has response
    # so get_response flag is ignored.
    return LWP::Simple.post( ~$uri, { 'Content-Type' => 'application/json' }, $json );
}

sub sequencer {
    state @pool = 'a' .. 'z', 'A' .. 'Z', 0 .. 9;

    return @pool.roll( 32 ).join( );
}

method sink () { self }

method !handler( Str :$method!, :$params ) {

    # SPEC: Request object
    my %request = (

        # SPEC: A String specifying the version of the JSON-RPC protocol.
        # MUST be exactly "2.0".
        'jsonrpc' => '2.0',

        # SPEC: A String containing the name of the method to be invoked.
        'method' => $method,
    );

    # SPEC: An identifier established by the Client
    # that MUST contain a String, Number, or NULL value if included.
    # If it is not included it is assumed to be a notification.
    %request{'id'} = $!sequencer( ) unless $.is_notification;

    # SPEC: A Structured value that holds the parameter values
    # to be used during the invocation of the method.
    # This member MAY be omitted.
    %request{'params'} = $params if $params.defined;

    # Requests in Batch are not processed until rpc.flush method is called.
    if $.is_batch {
        @!stack.push( $%request );
        return;
    }

    my $request = to-json( %request );

    # SPEC: Response object
    my $response;

    # SPEC: A Request object that is a Notification signifies
    # the Client's lack of interest in the corresponding Response object.
    if $.is_notification {
        $!transport( json => $request, get_response => False );
        return;
    }
    else {
        $response = $!transport( json => $request, get_response => True );
    }

    $response = self!parse_json( $response );
    my $out = self!validate_response( $response );

    # failed procedure call, throw exception.
    $out.throw if $out ~~ X::JSON::RPC;

    # SPEC: This member is REQUIRED.
    # It MUST be the same as the value of the id member in the Request Object.
    X::JSON::RPC::ProtocolError.new(
        message => 'Request id is different than response id',
        data => { 'request' => %request, 'response' => $response }
    ).throw unless %request{'id'} eqv $response{'id'};

    # successful remote procedure call
    return $out;
}

method ::('rpc.batch') {
    return self.clone( :is_batch );
}

method ::('rpc.notification') {
    return self.clone( :is_notification );
}

method ::('rpc.flush') {

    my $requests = to-json( @!stack );

    # SPEC: The Server should respond with an Array
    # containing the corresponding Response objects,
    # after all of the batch Request objects have been processed.
    my $responses;

    if @!stack.grep: { $_{'id'}:exists } {
        $responses = $!transport( json => $requests, get_response => True );
    }
    # SPEC: If the batch rpc call itself fails to be recognized (...)
    # as an Array with at least one value,
    # the response from the Server MUST be a single Response object.
    elsif not @!stack.elems {
        $responses = $!transport( json => $requests, get_response => True );
    }
    # SPEC: If there are no Response objects contained within the Response array
    # as it is to be sent to the client, the server MUST NOT return an empty Array
    # and should return nothing at all.
    else {
        $!transport( json => $requests, get_response => False );
        @!stack = ( );

        return;
    }

    $responses = self!parse_json( $responses );

    # throw Exception if Server was unable to process Batch
    # and returned single Response object with error
    if $responses ~~ Hash {
        self!bind_error( $responses{'error'} ).throw;
    }

    for $responses.list -> $response {
        $response{'out'} = self!validate_response( $response );
    }

    # SPEC: A Response object SHOULD exist for each Request object,
    # except there SHOULD NOT be any Response objects for notifications.
    for @!stack.grep( { $_{'id'}:exists } ).kv -> $position, $request {

        # SPEC: The Client SHOULD match contexts between the set of Request objects
        # and the resulting set of Response objects based on the id member within each Object.
        my $found;

        # SPEC: The Response objects being returned from a batch call
        # MAY be returned in any order within the Array.
        for $responses[ $position .. * ].kv -> $subposition, $response {

            # most servers do not parallelize processing and change order of Responses
            # so id member at Request position (minus amount of previous Notifications)
            # and the same Response position in Batch should usually match on the first try
            next unless $response{'id'} eqv $request{'id'};

            # swap Responses at position being checked and desired position if not already in place
            $responses[ $position, $position + $subposition ] = $responses[ $position + $subposition, $position ]
                if $subposition;

            # extract relevant part of Response
            $responses[ $position ] = ( $response{'out'} ~~ X::JSON::RPC )
                ?? Failure.new( $response{'out'} )
                !! $response{'out'};

            $found = True;

            last;
        }

        next if $found;

        # if Response was not found by id member it must be Invalid Request error
        for $responses[ $position .. * ].kv -> $subposition, $response {

            next unless $response{'out'} ~~ X::JSON::RPC::InvalidRequest;

            # swap Responses at position being checked and desired position if not already in place
            $responses[ $position, $position + $subposition ] = $responses[ $position + $subposition, $position ]
                if $subposition;

            $responses[ $position ] = Failure.new( $response{'out'} );

            $found = True;

            last;
        }

        X::JSON::RPC::ProtocolError.new(
            message => 'Cannot match context between Requests and Responses in Batch',
            data => { 'requests' => @!stack, 'responses' => $responses }
        ).throw unless $found;

        LAST {
            X::JSON::RPC::ProtocolError.new(
                message => 'Amount of Responses in Batch higher than expected',
                data => { 'requests' => @!stack, 'responses' => $responses }
            ).throw if $position != $responses.elems - 1;
        }
    }

    # clear Requests stack
    @!stack = ( );

    return @($responses);
}

method !parse_json ( Str $body ) {

    my $parsed;

    try { $parsed = from-json( $body ); };

    X::JSON::RPC::ProtocolError.new( data => ~$! ).throw if defined $!;
    X::JSON::RPC::ProtocolError.new.throw unless $parsed ~~ Array|Hash;

    return $parsed;
}

method !validate_response ( $response ) {

    # SPEC: Response object
    # When a rpc call is made, the Server MUST reply with a Response,
    # except for in the case of Notifications.
    # The Response is expressed as a single JSON Object, with the following members:

    # SPEC: A String specifying the version of the JSON-RPC protocol.
    # MUST be exactly "2.0".
    subset MemberJSONRPC of Str where '2.0';

    # SPEC: This member is REQUIRED on success.
    # This member MUST NOT exist if there was an error invoking the method.
    subset MemberResult of Any;

    # SPEC: This member is REQUIRED on error.
    # This member MUST NOT exist if there was no error triggered during invocation.
    # (explained in "5.1 Error object", validated later)
    subset MemberError of Hash;

    # SPEC: This member is REQUIRED.
    # It MUST be the same as the value of the id member in the Request Object.
    subset MemberID where Str|Int|Rat|Num|Any:U;

    given $response {
        when :( MemberJSONRPC :$jsonrpc!, MemberResult :$result!, MemberID :$id! ) {
            return $response{'result'};
        }
        when :( MemberJSONRPC :$jsonrpc!, MemberError :$error!, MemberID :$id! ) {
            return self!bind_error( $response{'error'} );
        }
        default {
            X::JSON::RPC::ProtocolError.new(
                message => 'Invalid Response',
                data => $response
            ).throw;
        }
    }
}

method !bind_error ( $error ) {

    # SPEC: Error object
    # When a rpc call encounters an error,
    # the Response Object MUST contain the error member
    # with a value that is a Object with the following members:

    # SPEC: A Number that indicates the error type that occurred.
    # This MUST be an integer.
    subset ErrorMemberCode of Int;

    # SPEC: A String providing a short description of the error.
    # The message SHOULD be limited to a concise single sentence.
    subset ErrorMemberMessage of Str;

    # SPEC: A Primitive or Structured value that contains additional information about the error.
    # This may be omitted.
    subset ErrorMemberData of Any;

    X::JSON::RPC::ProtocolError.new(
        message => 'Invalid Error',
        data => $error
    ).throw unless $error ~~ :( ErrorMemberCode :$code!, ErrorMemberMessage :$message!, ErrorMemberData :$data? );

    given $error{'code'} {
        when -32700 {
            return X::JSON::RPC::ParseError.new( |$error );
        }
        when -32600 {
            return X::JSON::RPC::InvalidRequest.new( |$error );
        }
        when -32601 {
            return X::JSON::RPC::MethodNotFound.new( |$error );
        }
        when -32602 {
            return X::JSON::RPC::InvalidParams.new( |$error );
        }
        when -32603 {
            return X::JSON::RPC::InternalError.new( |$error );
        }
        default {
            return X::JSON::RPC.new( |$error );
        }
    }
}

=begin pod

=TITLE class JSON::RPC::Client

Client implementing JSON-RPC 2.0 protocol.

Please check online documentation at L<https://github.com/bbkr/jsonrpc>.

=end pod
