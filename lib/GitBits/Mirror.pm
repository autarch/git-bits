package GitBits::Mirror;

use Moose;
use namespace::autoclean;
use autodie qw( :all );

use Cwd qw( abs_path );
use File::Basename qw( basename );
use Git::Wrapper;
use Net::GitHub;
use Sys::Hostname qw( hostname );

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

has token => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build_token',
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

has _github => (
    is       => 'ro',
    isa      => 'Net::GitHub::V2',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_github',
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

    my %names
        = map { $_->{name} => 1 } @{ $self->_github()->repos()->list() };

    return if $names{ $self->repo() };

    $self->_out(
        'Creating new ' . $self->repo() . " repository on github" );

    my $repo = $self->_github()->repos()->create(
        $self->repo(),
        'Mirror of ' . $self->repo() . ' on ' . $self->_hostname(),
        undef,
        1,
    );

    return;
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

sub _build_owner {
    my $self = shift;

    return $self->_git_config('github.owner');
}

sub _build_token {
    my $self = shift;

    return $self->_git_config('github.token');
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

sub _build_github {
    my $self = shift;

    return Net::GitHub->new(
        owner => $self->owner(),
        login => $self->owner(),
        token => $self->token(),
        repo  => $self->repo(),
    );
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
