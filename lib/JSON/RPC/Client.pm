use URI;
use LWP::Simple;
use JSON::Tiny;
use JSON::RPC::Error;

class JSON::RPC::Client;

has Code $!transport is rw;
has Code $!sequencer is rw;
has Bool $.is_batch = False;
has Bool $.is_notification = False;
has @!stack = ( );

INIT {

    # install method auto dispatch
    $?PACKAGE.^add_fallback(

        # must return True or False to indicate if it can handle the fallback
        sub ( $object, $name ) { return True },
    
        # should return the Code object to invoke
        sub ( $object, $name ) {

            # placeholder variables cannot be passed-through
            # so dispatch has to be done manually depending on nature of passed params
            return method ( *@positional, *%named ) {
                if @positional  and %named {
                    JSON::RPC::ProtocolError.new(
                        message => 'Cannot use positional and named params at the same time.'
                    ).throw;
                }
                elsif @positional {
                    return $object!handler( method => $name, params => @positional );
                }
                elsif %named {
                    return $object!handler( method => $name, params => %named );
                }
                else {
                    return $object!handler( method => $name );
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
		@!stack.push( { %request } );
		
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
    
    my %response = self!parse_json( $response );
    my $version = self.validate_response( |%response );

    # Failed procedure call, throw exception.
    if %response{'error'}.defined {
        self.bind_error( |%response{'error'} ).throw;
    }

    # SPEC: This member is REQUIRED.
    # It MUST be the same as the value of the id member in the Request Object.
    unless %request{'id'} eqv %response{'id'} {
        JSON::RPC::TransportError.new( data => 'JSON RPC request id is different than response id' ).throw;
    }

    # successful remote procedure call
    return %response{'result'};
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
	
    if @!stack.grep: *.exists( 'id' ) {
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
		self.bind_error( |$responses{'error'} ).throw;
	}
	
    # SPEC: A Response object SHOULD exist for each Request object,
    # except there SHOULD NOT be any Response objects for notifications.
	for @!stack.grep( *.exists( 'id' ) ).kv -> $position, $request {

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
			$responses[ $position ] = $response.exists( 'error' )
			    ?? Failure.new( self.bind_error( |$response{'error'} ) )
			    !! $response{'result'};
			
			$found = True;
			
			last;
        }

		next if $found;
		
        # if Response was not found by id member it must be Invalid Request error
        for $responses[ $position .. * ].kv -> $subposition, $response {
            my $error = self.bind_error( |$response{'error'} );
            next unless $error ~~ JSON::RPC::InvalidRequest;
            
			# swap Responses at position being checked and desired position if not already in place
			$responses[ $position, $position + $subposition ] = $responses[ $position + $subposition, $position ]
				if $subposition;
			
			$responses[ $position ] = Failure.new( $error );
			
			$found = True;
			
			last;
        }
        
        JSON::RPC::ProtocolError.new(
            message => 'Cannot match contect between Requests and Responses in Batch.',
            data => { 'requests' => @!stack, 'responses' => $responses }
        ).throw unless $found;
		
    }
    
    # clear Requests stack
    @!stack = ( );
	
	return @($responses);
}

method !parse_json ( Str $body ) {

    my $parsed;

    try { $parsed = from-json( $body ); };

    JSON::RPC::TransportError.new( data => ~$! ).throw if defined $!;
    JSON::RPC::TransportError.new.throw unless $parsed ~~ Array|Hash;

    return $parsed;
}

multi method validate_response (

    # A String specifying the version of the JSON-RPC protocol. MUST be exactly "2.0".
    Str :$jsonrpc! where '2.0',

    # This member is REQUIRED on success.
    # This member MUST NOT exist if there was an error invoking the method.
    # INFO: as explained in RT 109182 lack of presence cannot be tested in signature
    # so "result":null is incorrectly assumed to be to be valid -
    # this is not dangerous because upper logic can recognize this case
    # HACK: mutually exclusive error and result members are checked later
    :$result?,

    # This member is REQUIRED on error.
    # This member MUST NOT exist if there was no error triggered during invocation.
    # INFO: as explained in RT 109182 lack of presence cannot be tested in signature
    # so "error":null is incorrectly assumed to be to be valid -
    # this is not dangerous because upper logic can recognize this case
    :$error? where {
        # test if error and result params are mutually exclusive
        # this check is performed even if error is not given
        ( $result.defined xor $error.defined )
        # INFO: error format is checked later
    },

    # This member is REQUIRED.
    # It MUST be the same as the value of the id member in the Request Object.
    # INFO: comparison with request id is on upper level 
    :$id!
) {
    # spec version number
    return 2.0;
}

multi method validate_response {

    # none of above spec signatures claimed protocol version number
    JSON::RPC::TransportError.new( data => 'JSON-RPC Response Object is not valid' ).throw;
}

multi method bind_error (
    # A Number that indicates the error type that occurred.
    # This MUST be an integer.
    Int :$code!,

    # A String providing a short description of the error.
    # The message SHOULD be limited to a concise single sentence.
    Str :$message!,

    # A Primitive or Structured value that contains additional information about the error.
    # This may be omitted.
    :$data?,
)
{
    given $code {
        when -32700 {
            return JSON::RPC::ParseError.new( data => $data);
        }
        when -32600 {
            return JSON::RPC::InvalidRequest.new( data => $data);
        }
        when -32601 {
            return JSON::RPC::MethodNotFound.new( data => $data);
        }
        when -32602 {
            return JSON::RPC::InvalidParams.new( data => $data);
        }
        when -32603 {
            return JSON::RPC::InternalError.new( data => $data);
        }
        default {
            return JSON::RPC::Error.new( code => $code, message => $message, data => $data );
        }
    }

}

multi method bind_error {

    # none of above spec signatures claimed error field format
    JSON::RPC::TransportError.new( data => 'JSON-RPC Response Object is not valid' ).throw;
}
