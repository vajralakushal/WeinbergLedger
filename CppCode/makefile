CC = gcc
CXX = g++

CFLAGS = -O2 -Wall
CXXFLAGS = -O2 -Wall

main: query.cpp sqlite3.o
	$(CXX) $(CXXFLAGS) query.cpp sqlite3.o -o query.exe

sqlite3.o: sqlite3.c
	$(CC) $(CFLAGS) -c sqlite3.c

clean:
	-del *.o query.exe