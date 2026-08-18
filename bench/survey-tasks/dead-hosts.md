# Task: stop the crawler chasing hosts that will never answer


The crawler keeps going back to hosts that are never going to reply. A domain whose DNS does not
resolve, or that refuses every connection it is offered, gets picked up again on the very next
batch of work and spends a worker slot finding out the same thing it found out last time. The same
handful of dead domains come round and round.

I want the crawler to remember which hosts have proved themselves unreachable, and to stop handing
those hosts out as work.

Two things matter to me beyond that. A host that has only just started failing should not be
written off permanently — something that is down this afternoon may be up tomorrow, and I do not
want to lose a site forever because of one bad hour. And I want to be able to see which hosts are
currently being skipped, rather than having to infer it from the crawl slowing down.
