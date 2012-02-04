# JSON-RPC client and server

Implements [spec](http://jsonrpc.org/spec.html "2.0 specification").


## VERSION

This module is compatible with Rakudo Star 2012.01+.


## CLIENT

Work in progress


## SERVER

Define application class that will handle remote procedure calls.

    class My::App {
    
        # method without arguments
        method ping  { return 'pong' }
    
        # method with positional arguments
        method welcome ( Str $name! ) { return 'Hi ' ~ $name }

        # method with named arguments
        method welcome ( Str :$name! ) { return 'Hi ' ~ $name }
    
        # multi method with different signatures
        multi method offer ( Int $age where { $age < 8 } ) {
            return [ 'Toy' ];
        }
        multi method offer ( Int $age where { 8 <= $age <= 16 } ) {
            return [ 'Computer', 'Pet' ];
        }
    
    }

Start server with your application as handler.

    JSON::RPC::Server.new( application => My::App ).run;

Your server is now available at http://localhost:8080 .

Jump to advanced stuff below if you like...

### Application

* You can provide class name or object instance. Using class name results in static dispatch while using object instance allows you to initialize attributes in your class.

    class My::App {
    
        has $!db;
        submethod BEGIN { $!db = ... # connect to database  }
    
        method ping ( ) { return 'pong' }
    
    }
    
    # BEGIN is not called
    JSON::RPC::Server.new( application => My::App ).run;
    
    # or..
    
    # BEGIN is called
    JSON::RPC::Server.new( application => My::App.new ).run;

* Declare methods as private if you do not wish server to dispatch to them.

    method !get_database_info ( ) {
        return 'username', 'password';
    }

* Validate params in signatures instead of method bodies. This way server correctly returns 'Invalid params' error and method is not called if signature does not match - you can easily separate validation from logic.

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

* When request can be dispatched to more than one multi method then first candidate in definition order is chosen.

## ERRORS

Server supports errors defined in 2.0 spec.

* Parse error - Invalid JSON was received by the server.

* Invalid Request - The JSON sent is not a valid Request object.

* Method not found - The method does not exist in your application.

* Invalid params - Invalid method parameters, no candidates with matching signature found.

* Internal error - Your method died. Catched message is returned as 'data' explanation field in Error object.

    method divide ( Int $x, Int $y ) {
        die 'Cannot divide by 0' if $y ~~ 0;
        return $x / $y;
    }

* Custom error can be defined by composing JSON::RPC::Error exception. It is throwable.

    class My::Error does JSON::RPC::Error {
        submethod BUILD (
            $!code = -1,
            $!message = 'Access denied',
            $!data = 'Thou shall not pass'
        ) {}
    }
    
    class My::App {
    
        method treasure { My::Error.new.throw }
    
    }

## TODO

* Client
* Notification support in server
* Support for older spec versions
* Better documentation for RPC::Error namespace
* Better documentation for positional vs. named params

## CONTACT

You can find me (and many awesome people who helped me to develop this module)
on irc.freenode.net #perl6 channel as __bbkr__.