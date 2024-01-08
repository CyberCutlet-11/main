const express = require('express')
const app = express()
const os = require("os");
const hostname = os.hostname();

app.get('/', (req, res) => res.send(`Test website. Server running at ${hostname}`))
app.listen(3000, () => console.log('Server ready'))