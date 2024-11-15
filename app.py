from flask import Flask, render_template, request
import random

app = Flask(__name__)

# Dummy match data
teams = {
    "Team A": {
        "players": ["Player 1", "Player 2", "Player 3"],
        "scores": []
    },
    "Team B": {
        "players": ["Player 4", "Player 5", "Player 6"],
        "scores": []
    }
}

@app.route('/')
def home():
    return render_template("index.html", teams=teams)

@app.route('/score', methods=['POST'])
def score():
    team = request.form['team']
    player = request.form['player']
    runs = int(request.form['runs'])

    # Add score to the team's player list
    if team in teams:
        teams[team]["scores"].append({"player": player, "runs": runs})

    return render_template("index.html", teams=teams)

@app.route('/simulate', methods=['POST'])
def simulate():
    # Simulate a random match
    for team in teams.values():
        for player in team['players']:
            runs = random.choice([0, 4, 6])  # 0, 4, or 6 runs
            team['scores'].append({"player": player, "runs": runs})

    return render_template("index.html", teams=teams)

if __name__ == "__main__":
    app.run(debug=True)
