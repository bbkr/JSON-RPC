# JSON-RPC client and server

Supports [2.0 specification](http://www.jsonrpc.org/specification).

Compatible with Perl 6 [Rakudo](http://rakudo.org/) 2012.07+,
included in [Rakudo Star](https://github.com/rakudo/star) 2012.04+.

## CLIENT

```perl
   use JSON::RPC::Client;
   
   # create new client with url to server
   my $c = JSON::RPC::Client.new( url => 'http://localhost:8080' );
   
   # method without params    
   say $c.ping;
   
   # method with positional params
   say $c.hi( 'John Doe' );
   
   # method with named params
   say $c.hello( name => 'John Doe' );
```

## SERVER

```perl
    use JSON::RPC::Server;

    # define application class
    # that will handle remote procedure calls
    class My::App {
    
        # method without params
        method ping { return 'pong' }
    
        # method with positional params
        method hi ( Str $name! ) { return 'Hi ' ~ $name }

        # method with named params
        method hello ( Str :$name! ) { return 'Hello ' ~ $name }
    
        # multi method with different signatures
        multi method offer ( Int $age where { $age < 8 } ) {
            return [ 'Toy' ];
        }
        multi method offer ( Int $age where { 8 <= $age <= 16 } ) {
            return [ 'Computer', 'Pet' ];
        }
    
    }

    # start server with your application as handler
    JSON::RPC::Server.new( application => My::App ).run;
```

Your server is now available at [http://localhost:8080](http://localhost:8080).

## ADVANCED STUFF

Examples above _make easy things easy_, now it is time to make _hard things possible_.

### Protocol versions

There are 4 specs of JSON-RPC published so far:

* [1.0](http://json-rpc.org/wiki/specification) - Not implemented. Does not support named params, error objects or batch requests and has different way of handling notifications compared to current spec. It is rarely used nowadays and because of that there are no plans to implement it, however contributions are welcome if someone wants to add backward compatibility.
* [1.1](http://json-rpc.org/wd/JSON-RPC-1-1-WD-20060807.html) - Rejected. This working draft forces error reporting through HTTP codes making whole communication transport-dependent.
* [1.2](http://jsonrpc.org/historical/jsonrpc12_proposal.html) - Proposal of 2.0 (see below).
* [2.0](http://www.jsonrpc.org/specification) - Almost fully implemented. Notifications and batches are on TODO list.

### Can I use URI object to initialize client

Use uri param in constructor.

```perl
	JSON::RPC::Client.new( uri => URI.new( 'http://localhost:8080' ) );
```

### Can I bind server to port other than 8080?

Use port param in `run()` method.

```perl
    .run( port => 9999 );
```

### Should I use class name or object instance as server handler?

You can use both. Using class name results in static dispatch while using object instance allows you to initialize attributes in your class.

```perl
    class My::App {
    
        has $!db;
        submethod BEGIN { $!db = ... }  # connect to database
    
        method ping ( ) { return 'pong' }
    
    }
    
    # BEGIN is not called
    JSON::RPC::Server.new( application => My::App ).run;
    
    # BEGIN is called
    JSON::RPC::Server.new( application => My::App.new ).run;
```

### How can method be excluded from server handler dispatch?

Declare it as private.

```perl
    method !get_database_info ( ) {
        return 'username', 'password';
    }
```

### Should I declare signatures for server handler methods?

It is recommended that you validate params in signatures instead of method bodies. This way server correctly returns "Invalid params" error (more info later) and method is not called if signature does not match - you can easily separate validation from logic.

```perl
    method add_programmer (
        Str :$name!,
        Int :$age! where { $age >= 0 },
        Int :$experience! where { $experience <= $age }
    ) {
        # params can be trusted here
        # all fields are required and
        # negative age or experience exceeding age shall not pass
        $!db.insert( $name, $age, $experience );
    }
```

### What happens when more than one server handler candidate matches?

When request can be dispatched to more than one multi method then first candidate in definition order is chosen. This is not an error.

### Can I use my own transport layer in server?

Use `handle()` method that takes JSON request and returns JSON response (if any).
Remember that notifications do not return JSON and your transport also should not send any data back to the client.

Here is how FastCGI handling may look like.

```perl
	my $server = JSON::RPC::Server.new( application => My::App );
	
	while my $cgi = CGI::Fast.new {
		my $response = $server.handle( json => $cgi.param( 'POSTDATA' ) ) or return;
		
		print 'HTTP/1.0 200 OK' ~ \x0D\x0A"
            ~ 'Content-Type: application/json' ~ "\x0D\x0A"
            ~ 'Content-Length: ' ~ $response.encode( 'UTF-8' ).bytes ~ "\x0D\x0A"
            ~ "\x0D\x0A"
            ~ $response;
	}
```

### Error handling

Errors defined in 2.0 spec are represented by `JSON::RPC::Error` exceptions:

* `JSON::RPC::ParseError` - Invalid JSON was received by the server.
* `JSON::RPC::InvalidRequest` - The structure sent by client is not a valid Request object.
* `JSON::RPC::MethodNotFound` - The method does not exist in server handler application.
* `JSON::RPC::InvalidParams` - Invalid method parameters, no handler candidates with matching signature found.
* `JSON::RPC::InternalError` - Remote method died.
* `JSON::RPC::TransportError` - Client specific error that may happen on transport layer.

Every exception has numeric `code` attribute that indicates the error type that occurred, text `message` attribute that provides a short description of the error and optional `data` attribute that contains additional information about the error.

**Client** can catch those exceptions.

```perl
    try {
        $c.hello( 'John Doe' );
        CATCH {
            when JSON::RPC::MethodNotFound {
                say 'Server is rude';
            }
            default {
                # stringified exception is in human-readable form
                say ~$_;
            }
        }
    }
```

**Server** does all the exception handling automatically. For example if you provide application handler without some method client will receive "Method not found" error on call to this method. However if you want to report error from method it can be done in two ways.

* End method using die.

```perl
	method divide ( Int $x, Int $y ) {
	    die 'Cannot divide by 0' if $y ~~ 0;
	    return $x / $y;
	}
```

Client will receive `message` attribute 'Internal error' with explanation "Cannot divide by 0" as `data` attribute.

* Throw `JSON::RPC::Error` exception.

```perl
	class My::App {
	    method treasure {
	        JSON::RPC::Error.new( code => -1, message => 'Access denied', data => 'Thou shall not pass' ).throw;
	    }
	}
```

Exception `JSON::RPC::Error` is composable so you can easily define your own errors.

```perl
    class My::Error does JSON::RPC::Error {
        method new {
            self.bless( *, code => -1, message => "Access denied", data => "Thou shall not pass" );
        }
    }
```

And use them in application handler.

```perl
    method treasure {
        My::Error.new.throw;
    }
```

##CHANGELOG

* 0.3 - compatibility fixes for Rakudo Star 2012.02
* 0.2 - working server, compatibility fixes for Rakudo NOM
* 0.1 - working client with 1.0 spec support

##LICENSE

Released under [Artistic License 2.0](http://www.perlfoundation.org/artistic_license_2_0).

## CONTACT

You can find me (and many awesome people who helped me to develop this module)
on irc.freenode.net #perl6 channel as **bbkr**.