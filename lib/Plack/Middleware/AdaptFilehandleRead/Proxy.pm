use strict;
use warnings;

package Plack::Middleware::AdaptFilehandleRead::Proxy;

sub new {
  my ($class, $target, $chunksize) = @_;
  die "$target doens't have a read method" unless $target->can('read');
  return bless +{ _t => $target, _cs => ($chunksize|| 4096), _buff=> ''}, $class;
}


sub getline {
  my $fh = (my $self = shift)->{_t};

  if(!defined($/)) {
    # slurp mode, we pray we never see this..
    die "Slurping not supported, patches welcomed";
  } elsif(ref($/)) {
    # fixed chunk mode
    my $chunk;
    my $len = +${$/};
    if($fh->read($chunk,$len)) {
      return $chunk;
    } else {
      return;
    }
  } elsif($/ eq "") {
    # Nullstring mode
    die "Null not supported, patches welcomed";
  } else {
    # We assume character delim mode... There's a few other weird options
    # but I doubt we'll see them in the context of a Plack handler.

    # If the buffer is undef, that means we've read it all
    return unless defined($self->{_buff});
    # If the current temporary read buffer has a newline
    if( (my $idx = index($self->{_buff}, $/)) >= 0) {
      #remove from the start of the buffer to the newline and return it
      my $line = substr($self->{_buff}, 0, $idx+1);
      $self->{_buff} = substr($self->{_buff},$idx+1);
      return $line;
    } else {
      # read a chunk into the temporary buffer and try again
      my $chunk;
      $fh->read($chunk,$self->{_cs});
      if($chunk) {
        $self->{_buff} .= $chunk;
        return $self->getline;
      } else {
        # no more chunks? just return what is left...
        return my $last_line = delete $self->{_buff};
      }
    }
  } 
}

sub AUTOLOAD {
  my ($self, @args) = @_;
  my ($method) = (our $AUTOLOAD =~ /([^:]+)$/);
  return $self->{_t}->$method(@args)
}

1;

=head1 NAME
 
Plack::Middleware::AdaptFilehandleRead::Proxy - Wrap an object to supply missing getline

=head1 SYNOPSIS

    my $new_fh = Plack::Middleware::AdaptFilehandleRead::Proxy->new($old_fh);
 
=head1 DESCRIPTION

Wraps a filehandle like object that has a read method and provides a getline
method that works as in L<IO::Filehandle>  All other method calls will be
delegated to the original object.

This is used primarily to adapt a filehandle like object that does C<read>
but not C<getline> so that you can use it as the body value for a L<PSGI>
response.  For example, L<MogileFS::Client> can return such a custom filehandle
like object and you may wish to use that response to stream via a L<PSGI>
application.

When adapting C<read> to C<getline> we call C<read> and ask for chunks of 4096
bytes.  This may or may not be ideal for your data, in which case you may wish
to override it as so:

  my $new_fh = Plack::Middleware::AdaptFilehandleRead::Proxy
    ->new($old_fh, $chunksize);

Please be aware that the chunksize is read into memory.  Also please note that
this chunksize is only used if C<$/> is set to a normal delimiter value (by 
default this is "/n".  If it is set to a scalar ref (as it is normally done by
most L<Plack> handlers) such as "$/ = \'4096'" then that scalar ref defines the
chunk length for read.  In other works, typically plack prefers C<getline> to
return chunks of a predefined length, although as the L<PSGI> specification indicates
this support of "$/" is considered optional for a custom filehandle like body.
We choose to support it since it can help avoid a situation where your entire
file gets read into memory when the file does not contain newlines (or whatever
$/ is set to).

=head1 METHODS

This class defines the following methods

=head2 getline

returns a line from the file, as described by L<IO::Filehandle>, suitable for
the L<PSGI> requirement of a filehandle like object.  It work by calling C<read>
in chunks, and returns lines.

=head2 AUTOLOAD

Used to delegate all other method calls to the underlying wrapped instance.
 
=head1 SEE ALSO
 
L<Plack>, L<Plack::Middleware>.
 
=head1 AUTHOR
 
John Napiorkowski L<email:jjnapiork@cpan.org>
 
=head1 COPYRIGHT & LICENSE
 
Copyright 2014, John Napiorkowski L<email:jjnapiork@cpan.org>
 
This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.
 
=cut
