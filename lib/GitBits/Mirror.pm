package GitBits::Mirror;

use Moose;
use namespace::autoclean;
use autodie qw( :all );

use Cwd qw( abs_path );
use File::Basename qw( basename );
use Git::Wrapper;
use JSON::XS;
use LWP::Protocol::https;
use LWP::UserAgent;
use MIME::Base64 qw( encode_base64 );
use Sys::Hostname qw( hostname );
use URI::FromHash qw( uri );

with 'MooseX::Getopt::Dashes';

has owner => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build_owner',
);

has login => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build_login',
);

has password => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build_password',
);

has cwd => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has repo => (
    is       => 'ro',
    isa      => 'Str',
    lazy    => 1,
    builder => '_build_repo',
);

has _hostname => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build_hostname',
);

has _ua => (
    is      => 'ro',
    isa     => 'LWP::UserAgent',
    lazy    => 1,
    builder => '_build_ua',
);

has _json => (
    is      => 'ro',
    isa     => 'JSON::XS',
    lazy    => 1,
    default => sub { JSON::XS->new()->utf8() },
);

has _git => (
    is       => 'ro',
    isa      => 'Git::Wrapper',
    init_arg => undef,
    lazy     => 1,
    default  => sub { Git::Wrapper->new( $_[0]->cwd() ) },
);

sub run {
    my $self = shift;

    $self->_maybe_create_repo();
    $self->_push_all();
}

sub _maybe_create_repo {
    my $self = shift;

    my %names = map { $_->{name} => 1 } $self->_get_all_repos();

    return if $names{ $self->repo() };

    $self->_out(
        'Creating new ' . $self->repo() . " repository on github" );

    my $resp = $self->_ua()->post(
        $self->_uri('/user/repos'),
        Content => $self->_json()->encode(
            {
                name        => $self->repo(),
                description => 'Mirror of '
                    . $self->repo() . ' on '
                    . $self->_hostname(),
                has_issues    => 0,
                has_wiki      => 0,
                has_downloads => 0,
            }
        ),
    );

    $self->_maybe_handle_error($resp);

    return;
}

sub _get_all_repos {
    my $self = shift;

    my $uri = $self->_uri(
        '/users/' . $self->owner() . '/repos',
        { per_page => 100 },
    );

    my @repos;

    while ($uri) {
        my $resp = $self->_ua()->get($uri);
        $self->_maybe_handle_error($resp);

        push @repos, @{ $self->_json()->decode( $resp->content() ) };

        my $next = $self->_find_next_page( $resp->header('Link') );
        $uri = $next && $next ne $uri ? $next : undef;
    }

    return @repos;
}

sub _find_next_page {
    my $self = shift;
    my $header = shift;

    return unless $header;

    my %links;
    for my $link ( split /\s*,\s*/, $header ) {
        next unless $link =~ /<([^>]+)>;\s*rel="([^"]+)"/;
        $links{$2} = $1;
    }

    return $links{next};
}

sub _maybe_handle_error {
    my $self = shift;
    my $resp = shift;

    return if $resp->is_success();

    my $body
        = $resp->content()
        ? $self->_json()->decode( $resp->content() )
        : { message => 'no body' };

    my $error = sprintf(
        "Error from github (%s):\n%s", $resp->code(),
        $body->{message}
    );

    die $error;
}

sub _push_all {
    my $self = shift;

    $self->_maybe_add_github_remote();

    $self->_out('Pushing all branches to github');

    $self->_git()->push( '--mirror', 'github' );

    return;
}

sub _maybe_add_github_remote {
    my $self = shift;

    my %remotes = map { $_ => 1 } $self->_git()->remote('show');
    return if $remotes{github};

    $self->_out('Adding github as new remote');

    $self->_git()
        ->remote( 'add', 'github',
        'git@github.com:' . $self->owner() . '/' . $self->repo() . '.git' );

    return;
}

sub _uri {
    my $self  = shift;
    my $path  = shift;
    my $query = shift;

    return uri(
        scheme => 'https',
        host   => 'api.github.com',
        path   => $path,
        query  => $query // {},
    );
}

sub _build_owner {
    my $self = shift;

    return $self->_git_config('github.owner');
}

sub _build_login {
    my $self = shift;

    return $self->owner();
}

sub _build_password {
    my $self = shift;

    return $self->_git_config('github.password');
}

sub _git_config {
    my $self = shift;
    my $name = shift;

    my $value = `git config --global $name`;

    die "Could not find a $name key in the global git config\n"
        unless defined $value && length $value;

    chomp $value;

    return $value;
}

sub _build_repo {
    my $self = shift;

    my $basename = basename( abs_path('.') );
    $basename =~ s/\.git//;

    return $basename;
}

sub _build_hostname {
    my $self = shift;

    return hostname();
}

sub _build_ua {
    my $self = shift;

    my $ua = LWP::UserAgent->new();

    my $login = join ':', $self->login(), $self->password();
    $ua->default_header( 'Authorization', 'Basic ' . encode_base64($login) );

    return $ua;
}

sub _out {
    my $self = shift;

    print @_, "\n";
}

__PACKAGE__->meta()->make_immutable();

1;

#ABSTRACT: Post-receive hook to mirror a repo to github

__END__

Manual steps needed:

* Set up keys on server side's git user
* Make sure github host key is known by server side git user
* Add post-receive hook
