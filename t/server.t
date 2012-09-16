BEGIN { @*INC.unshift('lib') }

use Test;
use JSON::RPC::Server;

plan( 51 );

class CustomError does JSON::RPC::Error {
    method new {
        self.bless( *, code => -1, message => "GLaDOS", data => "The cake was a lie." );
    }
}

class Application {
    
    multi method substract ( $subtrahend!, $minuend! ) { return $subtrahend - $minuend }

#    multi method echo { return }
#    multi method echo ( Str $scream ) { return $scream }
#    multi method echo ( Str :$scream ) { return $scream }

#    method naughty ( Int :$age! where { $age >= 18 } ) { "You bad boy..." }

#    multi method suicide ( Bool :$note! ) { die "The cake is a lie!" }
#    multi method suicide { CustomError.new.throw }

#    method !toothbrush { "No!" }
}

my $rpc = JSON::RPC::Server.new( application => Application );

isa_ok $rpc, JSON::RPC::Server;


{
    say $rpc.handler( json => '{"jsonrpc":"2.0","method":"subtract","params":[42,23],"id":1}' );
}