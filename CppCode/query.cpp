#include <iostream>
#include <vector>
#include <string>
#include <stdio.h>
#include "sqlite3.h"
#include <sys/time.h>

using namespace std;

/* Store query results */
vector<vector<string>> results;

/* Function declarations */
static int selectData(const char* dbPath, const string& searchTerm);
static int callback(void* data, int argc, char** argv, char** azColName);

int main(int argc, char* argv[])
{
    ios::sync_with_stdio(false);
    struct timeval start, stop; 
    double total_time;

    if (argc < 2) {
        cerr << "Usage: ./test.exe SEARCH_TERM" << endl;
        return 1;
    }

    string searchTerm = argv[1];

    const char* dir =
        "..\\library.db";


    gettimeofday(&start, NULL);
    selectData(dir, searchTerm);
    gettimeofday(&stop, NULL); 
    total_time = (stop.tv_sec-start.tv_sec)+0.000001*(stop.tv_usec-start.tv_usec);
    printf("Total Time: %8.4f\n seconds",	 total_time);

    /* Print results AFTER query completes */
    cout << "\n===== QUERY RESULTS =====\n" << endl;

    for (const auto& row : results) {

        for (const auto& value : row) {
            cout << value << " | ";
        }

        cout << endl;
    }

    return 0;
}

static int selectData(const char* dbPath, const string& searchTerm)
{
    sqlite3* DB;
    char* messageError;

    int exit = sqlite3_open(dbPath, &DB);

    if (exit != SQLITE_OK) {
        cerr << "Cannot open database." << endl;
        return 1;
    }

    /* Build SQL query dynamically */
    string sql =
        "SELECT * FROM LIBRARY WHERE TITLE LIKE '%" +
        searchTerm +
        "%';";

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

    exit = sqlite3_close(DB);

    if (exit != SQLITE_OK) {
        cerr << "Failed to close database." << endl;
    }

    return 0;
}

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