unit module Rakudoc::CMD;

use Rakudoc;

our proto sub MAIN(|) is export(:MAIN) {
    {*}
}

# $*USAGE shows the type name as, e.g., "[-d|--doc=<Directory> ...]", so the
# singular ("Directory") reads better, even though it is an array
subset Directory of Positional where { all($_) ~~ Str };

multi sub MAIN(
    #| Example: 'IO::Path' 'IO::Path.dir' '.dir'
    *@query ($, *@),

    #| Additional directories to search for documentation
    Directory :d(:$doc) = Empty,
    #| Use only directories specified with --doc / $RAKUDOC
    Bool :D(:$no-default-docs),

    Bool :v(:$verbose),     #= Chatty
    Bool :q(:$quiet),       #= Taciturn
) {
    my $rkd = Rakudoc.new:
        :doc-source($doc),
        :$no-default-docs,
        :$verbose,
        :$quiet,
        ;

    my @requests = @query.map: { $rkd.request: $_ };
    my @docs = @requests.map: { | .search };
    $rkd.display(|@docs);
}

multi sub MAIN(
    #| Index all documents found in doc directories
    Bool :b(:$build-index)!,

    #| Additional directories to search for documentation
    Directory :d(:$doc) = Empty,
    #| Use only directories specified with --doc / $RAKUDOC
    Bool :D(:$no-default-docs),

    Bool :v(:$verbose),
    Bool :q(:$quiet),
) {
    my $rkd = Rakudoc.new:
        :doc-source($doc),
        :$no-default-docs,
        :$verbose,
        :$quiet,
        ;

    $rkd.build-index;
}

multi sub MAIN(
    Bool :V(:$version)!,
) {
    put "$*PROGRAM :auth<{Rakudoc.^auth}>:api<{Rakudoc.^api}>:ver<{Rakudoc.^ver}>";
}

# NOTE: This multi will match anything, and print usage info; if -h is
# specified, exit 0 (success), otherwise error.
multi sub MAIN(
    Bool :h(:$help),

    #| Additional directories to search for documentation
    Directory :d(:$doc) = Empty,
    #| Use only directories specified with --doc / $RAKUDOC
    Bool :D(:$no-default-docs),

    # NB: Match anything!
    |
) {
    my $rkd = Rakudoc.new:
        :doc-source($doc),
        :$no-default-docs,
        ;
    &*USAGE(:okay($help), :rakudoc($rkd));
}
