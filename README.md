# JSON-RPC client and server

Supports [2.0 specification](http://www.jsonrpc.org/specification).

Compatible with Perl 6 [Rakudo](http://rakudo.org/) 2013.09+,
included in [Rakudo Star](https://github.com/rakudo/star) since 2012.04.

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
* [1.1](http://web.archive.org/web/20100718181845/http://json-rpc.org/wd/JSON-RPC-1-1-WD-20060807.html) - Rejected. This working draft forces error reporting through HTTP codes making whole communication transport-dependent.
* [1.2](http://jsonrpc.org/historical/jsonrpc12_proposal.html) - Proposal of 2.0 (see below).
* [2.0](http://www.jsonrpc.org/specification) - Fully implemented!

### Can I use URI object to initialize client?

Use `uri` param in constructor.

```perl
    JSON::RPC::Client.new( uri => URI.new( 'http://localhost:8080' ) );
```

### Can I bind server to port other than 8080?

Use `port` param in `run( )` method.

```perl
    JSON::RPC::Server.new( application => My::App ).run( port => 9999 );
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

When request can be dispatched to more than one multi method then first candidate is chosen and called. JSON-RPC protocol design does not include multi methods - it can not mimic [calling sets](http://perlcabal.org/syn/S12.html#Calling_sets_of_methods) mechanism and does not have "Ambiguous call" error in specification like Perl 6 does. Therefore such request is not considered an error.

### Can I use my own transport layers?

This is useful when you want to use JSON-RPC on some framework which provides its own data exchange methods. It is even possible to use JSON-RPC over protocols different than HTTP.

**Client**

Pass `transport` param to `new( )` instead of `uri`/ `url` param. This should be a closure that accepts JSON request and returns JSON response.

```perl
    sub transport ( Str :$json, Bool :$get_response ) {
        return send_request_in_my_own_way_and_obtain_response_if_needed( $request );
    }

    my $client = JSON::RPC::Client.new( transport => &transport );
```

Your transport will be given extra param `get_response` which informs if response is expected from the server or not (for example in case of Notification or Batch of Notifications).

**Server**

Do not `run( )` server. Instead use `handler( )` method which takes JSON request param and returns JSON response.

```perl
    my $server = JSON::RPC::Server.new( application => My::App );

    my $response = handler( json => receive_request_in_my_own_way( ) );
    send_response_in_my_own_way( $response ) if defined $response;
```

It is possible that request is a Notification or Batch of Notifications and `$response` is not returned from the server.

**Notifications**

When request is a Notification or Batch of Notifications then client is not expecting response and server should not return one. That is not always possible due to specification of used protocol or assumptions in framework used. In this case try to use most undefined response possible.

For example code `204 No Content` should be used in HTTP transport.

### How to enable debugging?

**Client** has no debugging yet.

**Server** accepts `debug` param in `run( )` method.

```perl
    JSON::RPC::Server.new( application => My::App ).run( :debug );
```

### How to implement Error handling?

Errors defined in 2.0 spec are represented by `X::JSON::RPC` exceptions:

* `X::JSON::RPC::ParseError` - Invalid JSON was received by the server.
* `X::JSON::RPC::InvalidRequest` - The structure sent by client is not a valid Request object.
* `X::JSON::RPC::MethodNotFound` - The method does not exist in server handler application.
* `X::JSON::RPC::InvalidParams` - Invalid method parameters, no handler candidates with matching signature found.
* `X::JSON::RPC::InternalError` - Remote method died.
* `X::JSON::RPC::ProtocolError` - Other deviation from specification.

Every exception has numeric `code` attribute that indicates the error type that occurred, text `message` attribute that provides a short description of the error and optional `data` attribute that contains additional information about the error.

**Client** can catch those exceptions.

```perl
    try {
        $c.hello( 'John Doe' );
        CATCH {
            when X::JSON::RPC::MethodNotFound {
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

Client will receive `message` attribute "Internal error" with explanation "Cannot divide by 0" as `data` attribute.

* Throw `X::JSON::RPC` exception.

```perl
    class My::App {
        method treasure {
            X::JSON::RPC.new( code => -1, message => 'Access denied', data => 'Thou shall not pass!' ).throw;
        }
    }
```

Exception `X::JSON::RPC` is composable so you can easily define your own errors.

```perl
    class My::Error does X::JSON::RPC {
        method new {
            self.bless( code => -1, message => 'Access denied', data => 'Thou shall not pass!' );
        }
    }
```

And use them in application handler.

```perl
    method treasure {
        My::Error.new.throw;
    }
```

### How to make Notification call?

Method `'rpc.notification'( )` puts client in notification context.
Note that this method contains dot in name and it must be quoted.

```perl
    $client.'rpc.notification'( ).heartbeat( ); # no response from this one
    say $client.ping( ) # regular call again
```

You can save client context to avoid typing.

```perl
    my $n = $client.'rpc.notification'( );
    for ^1024 {
        $n.heartbeat( ); # no responses from those
    }
```

### How to make Batch call?

Method `'rpc.batch'( )` puts client in batch context while method `'rpc.flush'( )` sends Requests.
Note that those methods contain dot in names and they must be quoted.

```perl
    $client.'rpc.batch'( ).add( 2, 2 );
    $client.'rpc.batch'( ).'rpc.notification'( ).heartbeat( );
    $client.'rpc.batch'( ).suicide( );

    for $client.'rpc.flush'( ) -> $response {
        try {
            $response.say;
            CATCH {
                when X::JSON::RPC {
                    say 'Oops! ', .message;
                }
            }
        }
    }

    # Output:
    # 4
    # Opps! Suicide served.
```

Important things to remember:

* Server may process methods in Batch in any order and with any width of parallelism.
* Client will sort responses to match order in which methods were stacked.
* Notifications do not have corresponding response.
* Batch containing only Notifications will return Nil on flush.
* Attempt to flush empty Batch will result in `X::JSON::RPC::InvalidRequest` exception.
* Individual exceptions are returned as Failures, thrown when called in sink context.

You can save client context to avoid typing.

```perl
    my $b = $client.'rpc.batch'( );
    for ^1024 {
        $b.is_prime( $_ );
    }
    my @responses = $b.'rpc.flush'( );
```

### How to call method that has name used by language itself?

Every object instance has some methods inherited from [Mu](http://doc.perl6.org/type/Mu) and [Any](http://doc.perl6.org/type/Any) classes.
This rule also applies to `JSON::RPC::Client` and in rare cases you may fall into the trap.
Below example calls `Mu::can( )` instead of doing remote procedure call of method named "can".

```
    $client.can( 'tuna' );

```

The workaround is to prefix method name with `rpc.`.
Note that whole name must be quoted because it contains dot.

```
    $client.'rpc.can'( 'tuna' );

```

You can get full list of those troublemakers by invoking following code.

```
    JSON::RPC::Client.^mro>>.^methods>>.say
```

## LICENSE

Released under [Artistic License 2.0](http://www.perlfoundation.org/artistic_license_2_0).

## CONTACT

You can find me (and many awesome people who helped me to develop this module)
on irc.freenode.net #perl6 channel as **bbkr**.
