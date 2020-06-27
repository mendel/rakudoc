unit class Pod::From::Cache;

role X::Pod::From::Cache is Exception {
}

class X::Pod::From::Cache::NoPodInCache is X::Pod::From::Cache {
    has @.doc-source;
    has $.pod-file-path;
    method message {
        "No pod in {@!doc-source.map(*.Str.raku).join(', ')} "
        ~ "for {$!pod-file-path.Str.raku}. Has the path changed?"
    }
}

class X::Pod::From::Cache::NoSources does X::Pod::From::Cache {
    has @.doc-source;
    method message { "No pod sources in @!doc-source.map(*.Str.raku).join(', ')." }
}

class X::Pod::From::Cache::BadSource does X::Pod::From::Cache {
    has %.errors;
    method message {
        %!errors.fmt("File source %s has error:\n%s").join("\n")
    }
}


has IO::Path @!doc-source;
has @.extensions;
has $!cache-path;
has $!lazy;
has $!precomp-repo;
has @.refreshed-pods;
has @.sources;
has %!errors;
has %!ids;
has SetHash $!ignore .= new;

submethod BUILD(
    # TODO Put rakudoc first once Raku/doc repo switches to it
    :@!extensions = <pod6 rakudoc pod p6 pm pm6>,
    :@doc-source,
    :$!cache-path = 'rakudoc_cache', # trans OS default directory name
    :$!lazy,
) {
    @!doc-source = grep *.d, map {
            $_ eq ':DEFAULT'
                ?? | $*REPO.repo-chain.map({.?abspath.IO // Empty})».add('doc')
                !! .IO.resolve(:completely)
        }, @doc-source || ':DEFAULT';
    X::Pod::From::Cache::NoSources.new(:@!doc-source).throw unless @!doc-source;

    $!precomp-repo = CompUnit::PrecompilationRepository::Default.new(
        :store(CompUnit::PrecompilationStore::File.new(:prefix($!cache-path.IO))),
    );
}

method !path-for-fragment($fragment is copy) {
    note "looking for $fragment";
    # Note: IO::Spec::Win32.splitdir splits on both '/' and '\', so
    # $fragment can be a Unixy or OS-specific path
    my @parts = $*SPEC.splitdir($fragment);
    $fragment = $*SPEC.catdir(@parts).IO;

    my $matrix = (@!doc-source X ($fragment.extension ?? '' !! @!extensions));

    for @$matrix -> ($dir, $ext) {
        my $path = $dir.add($fragment).extension(:0parts, $ext);
        note "  - $path";
        return ~$path if $path.e;
    }
    X::Pod::From::Cache::NoPodInCache.new(:@!doc-source, :pod-file-path($fragment)).throw;
}

submethod TWEAK {
    # get the .ignore-cache contents, if it exists and add to a set.
    my $ignore = @!doc-source.first.add('.ignore-cache');
    if $ignore.f {
        for $ignore.lines {
            $!ignore{ self!path-for-fragment(.trim) }++;
        }
    }

    return if $!lazy;

    self.get-pods;
    X::Pod::From::Cache::NoSources.new(:@!doc-source).throw
        unless @!sources;

    self!load-pod($_) for @!sources;

    X::Pod::From::Cache::BadSource.new(:errors(%!errors.list)).throw
        if %!errors;
}

method !load-pod($pod-file-path) {
    my $t = $pod-file-path.IO.modified;
    my $id = CompUnit::PrecompilationId.new-from-string($pod-file-path);
    %!ids{$pod-file-path} = $id.id;
    my $handle;
    my $checksum;
    try {
        ($handle, $checksum) = $!precomp-repo.load( $id, :src($pod-file-path), :since($t) );
    }
    if $! or ! $checksum.defined {
        @!refreshed-pods.push($pod-file-path);
        $handle = $!precomp-repo.try-load(
            CompUnit::PrecompilationDependency::File.new(
                :src($pod-file-path),
                :$id,
                :spec(CompUnit::DependencySpecification.new(:short-name($pod-file-path))),
            )
        )
    }

    CATCH {
        default {
            %!errors{$pod-file-path} = .message.Str;
        }
    }

    $handle
}

#| Recursively finds all rakupod files with extensions in @!extensions
#| Returns an array of Str
method get-pods {
    @!sources = map my sub recurse ($dir) {
        gather for dir($dir) {
            when $!ignore{$_} { }
            when '.precomp' { }
            when .d { take slip sort recurse $_ }
            when  *.extension eq any( @!extensions ) { take .Str }
        }
    }, @!doc-source;
}

#| pod(Str $pod-file-path) returns the pod tree in the pod file
method pod( Str $pod-file-path is copy ) {
    use nqp;

    $pod-file-path = self!path-for-fragment($pod-file-path)
        unless $pod-file-path.IO.is-absolute;
    return Nil if $!ignore{$pod-file-path};

    my $handle;
    if %!ids{$pod-file-path}:exists {
        $handle = $!precomp-repo.try-load(
            CompUnit::PrecompilationDependency::File.new(
                :src($pod-file-path),
                :id(CompUnit::PrecompilationId.new(%!ids{$pod-file-path}))
                ),
            );
    }
    else {
        X::Pod::From::Cache::NoPodInCache.new(:@!doc-source, :$pod-file-path).throw
            unless $!lazy;
        $handle = self!load-pod($pod-file-path);
        X::Pod::From::Cache::BadSource.new(:errors(%!errors.list)).throw
            if %!errors;
        @!sources.push: $pod-file-path;
    }

    nqp::atkey( $handle.unit, '$=pod' )
}

#| removes the cache using OS dependent arguments.
our sub rm-cache($path = 'rakudo_cache' ) is export {
    if $*SPEC ~~ IO::Spec::Win32 {
        my $win-path = "$*CWD/$path".trans( ["/"] => ["\\"] );
        shell "rmdir /S /Q $win-path" ;
    } else {
        shell "rm -rf $path";
    }
}
