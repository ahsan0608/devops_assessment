const express = require('express');
const axios = require('axios');
const app = express();

app.get("/api", (req, res, next) => {
    res.json({"message": "Hello, World!"});
});

app.get("/pub/dummyfile", async (req, res) => {
    try {
        const response = await axios.get('https://ahsanselisestorage.blob.core.windows.net/ahsanselisecontainer/dummyfile.txt');
        res.send(response.data);
    } catch (error) {
        res.status(500).send("Error fetching the file");
    }
});

app.listen(3000, () => {
    console.log("Server running on port 3000");
});
