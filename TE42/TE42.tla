------------------------------- MODULE TE42 --------------------------------
EXTENDS Integers, Sequences, TLC
CONSTANTS RingBufSz
ASSUME RingBufSz \in Int

(******************************************************)
(*     Translation Engine 4 Algorithm Abstraction     *)
(*     with no batching                               *)
(******************************************************)

(***************************************************************************)
(*  For TLC:                                                               *)
(*  Use state constraint: Len(source) < 11 /\ Len(sink) < 13               *)
(*  Use RingBufSz = 16                                                     *)
(***************************************************************************)

(***************************************************************************
--algorithm TE42 {
    variables
      source = << >>,        \* starting source of messages
      sentUnacked = << >>,   \* msgs sent from JMS -> Inbounder, but unacked
      ackChan = << >>,       \* acks from Outbounder -> JMS, ack vals == uid
      sentAcked = << >>,     \* msgs sent from JMS -> Inbounder and acked by Outbounder
      ringBuffer = << >>,    \* RingBuffer is modeled as a simple FIFO
      sink = << >>;          \* final sink of messages


  \* transfer one entry on `from` seq to both `to1` and `to2` seqs
  macro DuplexTransferOne(from, to1, to2) {
    to1 := Append(to1, Head(from));
    to2 := Append(to2, Head(from));
    from := Tail(from);  
  }

  macro TransferOne(from, to) {
    to := Append(to, Head(from));
    from := Tail(from);    
  }

\*  macro PeekLast(seq, val) {
\*    val := seq[Len(seq)]
\*  }

  (*--------------------*)
  (*---- JMS Source ----*)
  (*--------------------*)  
  process (JMSSource = "jmsSource")  \* TODO: there can be multiples of these
    variables uid = 1, inmsg, ack, lastAcked;
  {
  js1:  while (TRUE) {
          either {                         
            (* Receive good data messages *)
            source := Append(source, uid);
            uid := uid + 1;
            
          } or {
            await Len(ackChan) > 0;
            ack := Head(ackChan);
            ackChan := Tail(ackChan);
            inmsg := Head(sentUnacked);
            assert ack = inmsg;
  
            if (Len(sentAcked) > 0) {
              lastAcked := sentAcked[Len(sentAcked)];
              print <<lastAcked, "lastAcked|ack", ack>>;
              assert lastAcked # ack;              
            };          
            
            TransferOne(sentUnacked, sentAcked);
          };
        };
  };
  
  (*-------------------*)
  (*---- Inbounder ----*)
  (*-------------------*)
  process (Inbounder = "inbounder") 
  {
  ib1:  while (TRUE) {
          await (Len(source) > 0 /\ (Len(ringBuffer) < RingBufSz));
          DuplexTransferOne(source, sentUnacked, ringBuffer);
        };
  }
  
  
  (*--------------------*)
  (*---- Outbounder ----*)
  (*--------------------*)
  process (Outbounder = "outbounder")
    variables event = -1;
  {
  ob1:  while (TRUE) {
          await Len(ringBuffer) > 0;
          event := Head(ringBuffer);
          TransferOne(ringBuffer, sink);
          ackChan := Append(ackChan, event);
          assert \A i \in 1..Len(sink) : (sink[i] = i);
          
          if (Len(ringBuffer) > 8) {
            print <<ackChan, "ackChan|sentAcked", sentAcked>>;
          };
        };
  }
}

***************************************************************************)
\* BEGIN TRANSLATION
CONSTANT defaultInitValue
VARIABLES source, sentUnacked, ackChan, sentAcked, ringBuffer, sink, uid, 
          inmsg, ack, lastAcked, event

vars == << source, sentUnacked, ackChan, sentAcked, ringBuffer, sink, uid, 
           inmsg, ack, lastAcked, event >>

ProcSet == {"jmsSource"} \cup {"inbounder"} \cup {"outbounder"}

Init == (* Global variables *)
        /\ source = << >>
        /\ sentUnacked = << >>
        /\ ackChan = << >>
        /\ sentAcked = << >>
        /\ ringBuffer = << >>
        /\ sink = << >>
        (* Process JMSSource *)
        /\ uid = 1
        /\ inmsg = defaultInitValue
        /\ ack = defaultInitValue
        /\ lastAcked = defaultInitValue
        (* Process Outbounder *)
        /\ event = -1

JMSSource == /\ \/ /\ source' = Append(source, uid)
                   /\ uid' = uid + 1
                   /\ UNCHANGED <<sentUnacked, ackChan, sentAcked, inmsg, ack, lastAcked>>
                \/ /\ Len(ackChan) > 0
                   /\ ack' = Head(ackChan)
                   /\ ackChan' = Tail(ackChan)
                   /\ inmsg' = Head(sentUnacked)
                   /\ Assert(ack' = inmsg', 
                             "Failure of assertion at line 55, column 13.")
                   /\ IF Len(sentAcked) > 0
                         THEN /\ lastAcked' = sentAcked[Len(sentAcked)]
                              /\ PrintT(<<lastAcked', "lastAcked|ack", ack'>>)
                              /\ Assert(lastAcked' # ack', 
                                        "Failure of assertion at line 60, column 15.")
                         ELSE /\ TRUE
                              /\ UNCHANGED lastAcked
                   /\ sentAcked' = Append(sentAcked, Head(sentUnacked))
                   /\ sentUnacked' = Tail(sentUnacked)
                   /\ UNCHANGED <<source, uid>>
             /\ UNCHANGED << ringBuffer, sink, event >>

Inbounder == /\ (Len(source) > 0 /\ (Len(ringBuffer) < RingBufSz))
             /\ sentUnacked' = Append(sentUnacked, Head(source))
             /\ ringBuffer' = Append(ringBuffer, Head(source))
             /\ source' = Tail(source)
             /\ UNCHANGED << ackChan, sentAcked, sink, uid, inmsg, ack, 
                             lastAcked, event >>

Outbounder == /\ Len(ringBuffer) > 0
              /\ event' = Head(ringBuffer)
              /\ sink' = Append(sink, Head(ringBuffer))
              /\ ringBuffer' = Tail(ringBuffer)
              /\ ackChan' = Append(ackChan, event')
              /\ Assert(\A i \in 1..Len(sink') : (sink'[i] = i), 
                        "Failure of assertion at line 92, column 11.")
              /\ IF Len(ringBuffer') > 8
                    THEN /\ PrintT(<<ackChan', "ackChan|sentAcked", sentAcked>>)
                    ELSE /\ TRUE
              /\ UNCHANGED << source, sentUnacked, sentAcked, uid, inmsg, ack, 
                              lastAcked >>

Next == JMSSource \/ Inbounder \/ Outbounder

Spec == Init /\ [][Next]_vars

\* END TRANSLATION

============================================================================
