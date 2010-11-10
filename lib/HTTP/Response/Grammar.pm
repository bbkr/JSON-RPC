grammar HTTP::Response::Grammar;

token TOP {
    ^
        <status> \n
        [ <header> \n ]*
        [ \n <content> ]?
    $
}

token status {
    <version> <space> <code> <space> <message>
}

token version {
    'HTTP/' [ '1.0' | '1.1' ]
}

token code {
    \d ** 3
}

token message {
    \N+
}

token header {
    \N+
}

token content {
    .+
}
