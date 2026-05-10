CC = gcc
CXX = g++
CFLAGS = -O3 -Wall
CXXFLAGS = -O3 -Wall

main: query.cpp sqlite3.o
	$(CXX) $(CXXFLAGS) query.cpp sqlite3.o -o query.exe

sqlite3.o: sqlite3.c
	$(CC) $(CFLAGS) -c sqlite3.c