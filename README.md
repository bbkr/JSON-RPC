# JSON-RPC client and server

Supports [spec](http://jsonrpc.org/spec.html "2.0 specification").

Compatible with Rakudo Star 2012.01+.

## CLIENT

    use JSON::RPC::Client;
    
    # create new client with url to server
    my $c = JSON::RPC::Client.new( url => 'http://localhost:8080' );
    
    # method without params    
    say $c.ping;
    
    # method with positional params
    say $c.hi( 'John Doe' );
    
    # method with named params
    say $c.hello( name => 'John Doe' );


## SERVER

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

Your server is now available at *http://localhost:8080*.

## ADVANCED STUFF

Examples above _make easy things easy_.
Now it is time to make _hard things possible_.

### Should I use class name vs object instance as server handler?

You can use both. Using class name results in static dispatch while using object instance allows you to initialize attributes in your class.

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


### How can method be excluded from server handler dispatch?

Declare it as private.

    method !get_database_info ( ) {
        return 'username', 'password';
    }

### Should I declare signatures for server handler methods?

It is recommended that you validate params in signatures instead of method bodies. This way server correctly returns 'Invalid params' error (more info later) and method is not called if signature does not match - you can easily separate validation from logic.

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

### What will happen when more than one server handler candidate matches?

When request can be dispatched to more than one multi method then first candidate in definition order is chosen. This is not an error.

### Can I bind server to other port that 8080?

Use port param.

    JSON::RPC::Server.new( port => 9999 ...

### Error handling

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

* Notification support in server
* 1.0 spec support
* Better documentation for RPC::Error namespace

## CONTACT

You can find me (and many awesome people who helped me to develop this module)
on irc.freenode.net #perl6 channel as __bbkr__.