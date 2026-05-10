#include <iostream>
#include <stdio.h>
#include "sqlite3.h"

using namespace std;

static int selectData(const char* s);
static int callback(void* NotUsed, int argc, char** argv, char** azColName);

int main()
{
    const char* dir = "..\\library.db";
    selectData(dir);
	
    return 0;
}

static int selectData(const char* s)
{
    sqlite3* DB;
    char* messageError;

    string sql = "SELECT * FROM LIBRARY WHERE TITLE LIKE '%FREED%';";

    int exit = sqlite3_open(s, &DB);

    if (exit != SQLITE_OK) {
        cerr << "Cannot open database." << endl;
        return 1;
    }

    exit = sqlite3_exec(DB, sql.c_str(), callback, NULL, &messageError);

    if (exit != SQLITE_OK) {
        cerr << "SQL Error: " << messageError << endl;
        sqlite3_free(messageError);
    }
    else {
        cout << "Records selected Successfully!" << endl;
    }

    exit = sqlite3_close(DB);

    if (exit != SQLITE_OK) {
        cerr << "Failed to close database." << endl;
    }

    return 0;
}

// retrieve contents of database used by selectData()
/* argc: holds the number of results, argv: holds each value in array, azColName: holds each column returned in array, */
static int callback(void* NotUsed, int argc, char** argv, char** azColName)
{
    for (int i = 0; i < argc; i++) {
        cout << azColName[i] << " = ";

        if (argv[i]) {
            cout << argv[i];
        } else {
            cout << "NULL";
        }

        cout << endl;
    }

    cout << "---------------------" << endl;

	return 0;

}
