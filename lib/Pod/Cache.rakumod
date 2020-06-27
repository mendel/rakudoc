unit class Pod::Cache;

role X::Pod::Cache is Exception {
}

class X::Pod::Cache::NoPodInCache is X::Pod::Cache {
    has $.pod-file-path;
    method message {
        "No pod for {$!pod-file-path.Str.raku}. Has the path changed?"
    }
}

class X::Pod::Cache::NoSources does X::Pod::Cache {
    has $.doc-source;
    method message { "No pod sources in {$!doc-source.Str.raku}." }
}

class X::Pod::Cache::BadSource does X::Pod::Cache {
    has %.errors;
    method message {
        %!errors.fmt("File source %s has error:\n%s").join("\n")
    }
}


has %.sources is SetHash;

has IO::Path $!cache-path;
has $!precomp-repo;
has %!errors;
has %!ids;


submethod BUILD(
    :$cache-path = 'rakudoc_cache',
)
{
    $!cache-path = $cache-path.IO.resolve(:completely);
    $!precomp-repo = CompUnit::PrecompilationRepository::Default.new(
        :store(CompUnit::PrecompilationStore::File.new(:prefix($!cache-path))),
    );
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
        $handle = $!precomp-repo.try-load(
            CompUnit::PrecompilationDependency::File.new(
                :src($pod-file-path),
                :$id,
                :spec(CompUnit::DependencySpecification.new(:short-name($pod-file-path))),
            )
        )
    }

    ++%!sources{$pod-file-path};
    return $handle;

    CATCH {
        default {
            die X::Pod::Cache::BadSource.new: :errors(.message)
        }
    }
}

#| pod(Str $pod-file-path) returns the pod tree in the pod file
method pod( Str $pod-file-path is copy ) {
    use nqp;

    # Canonical form for lookup consistency
    $pod-file-path = ~$pod-file-path.IO.resolve(:completely);

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
        $handle = self!load-pod($pod-file-path);
    }

    nqp::atkey( $handle.unit, '$=pod' )
}
