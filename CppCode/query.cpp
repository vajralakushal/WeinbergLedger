#include <iostream>
#include <vector>
#include <string>
#include <stdio.h>
#include "sqlite3.h"
#include <sys/time.h>

using namespace std;

/* Store all query results here */
vector<vector<string>> results;

/* Function declarations */
static int selectData(const char* s);
static int callback(void* data, int argc, char** argv, char** azColName);

int main()
{
    ios::sync_with_stdio(false);
    struct timeval start, stop; 
    double total_time;
    


    const char* dir =
        "C:\\Users\\yalam\\Documents\\devWeinbergLedger\\library.db";

    /* Run query and store results */
    gettimeofday(&start, NULL); 

    selectData(dir);

	gettimeofday(&stop, NULL); 
    total_time = (stop.tv_sec-start.tv_sec)+0.000001*(stop.tv_usec-start.tv_usec);
    printf("Total Time: %8.4f\n seconds",	 total_time);

    /* Print results AFTER query finishes */
    cout << "\n===== QUERY RESULTS =====\n" << endl;

    for (const auto& row : results) {

        for (const auto& value : row) {
            cout << value << " | ";
        }

        cout << endl;
    }

    return 0;
}

static int selectData(const char* s)
{
    sqlite3* DB;
    char* messageError;

    string sql =
        "SELECT * FROM LIBRARY WHERE TITLE LIKE '%FREED%';";

    int exit = sqlite3_open(s, &DB);

    if (exit != SQLITE_OK) {
        cerr << "Cannot open database." << endl;
        return 1;
    }

    /* Execute query */
    exit = sqlite3_exec(
        DB,
        sql.c_str(),
        callback,
        NULL,
        &messageError
    );

    if (exit != SQLITE_OK) {

        cerr << "SQL Error: " << messageError << endl;
        sqlite3_free(messageError);

    } else {

        cout << "Records fetched successfully.\n";
    }

    /* Close DB */
    exit = sqlite3_close(DB);

    if (exit != SQLITE_OK) {
        cerr << "Failed to close database." << endl;
    }

    return 0;
}

/* Callback now STORES rows instead of printing */
static int callback(
    void* data,
    int argc,
    char** argv,
    char** azColName
)
{
    vector<string> row;

    for (int i = 0; i < argc; i++) {

        if (argv[i]) {
            row.push_back(argv[i]);
        } else {
            row.push_back("NULL");
        }
    }

    results.push_back(row);

    return 0;
}