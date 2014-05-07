# change these to where your libpq and neko include dirs are
NEKODIR = /usr/lib/neko/include
ZMQDIR = /usr/local/include

CC = gcc

#CFLAGS = -w -fPIC -I $(PGSQLDIR) -I $(NEKODIR)
CFLAGS = -w -fPIC -I $(ZMQDIR) -I $(NEKODIR)
LDFLAGS = -shared -Wl,-soname,hxzmq.ndll -lc -lzmq

hxzmq.ndll: context.o device.o interrupt.o poller.o socket.o zmq.o
	$(CC) $(LDFLAGS) -o hxzmq.ndll context.o device.o interrupt.o poller.o socket.o zmq.o

context.o: context.c
	$(CC) $(CFLAGS) -c context.c -o context.o

device.o: device.c
	$(CC) $(CFLAGS) -c device.c -o device.o

interrupt.o: interrupt.c
	$(CC) $(CFLAGS) -c interrupt.c -o interrupt.o

poller.o: poller.c
	$(CC) $(CFLAGS) -c poller.c -o poller.o

socket.o: socket.c
	$(CC) $(CFLAGS) -c socket.c -o socket.o

zmq.o: zmq.c
	$(CC) $(CFLAGS) -c zmq.c -o zmq.o

all: hxzmq.ndll

clean:
	rm *.o hxzmq.ndll
