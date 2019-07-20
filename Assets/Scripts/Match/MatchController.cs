using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using TMPro;

public class MatchController : MonoBehaviour
{
  private float startTime;
  static public TextMeshProUGUI matchTextBox;
  static public TextMeshProUGUI timerTextBox;
  static public TextMeshProUGUI scoreTextBox;
  static public FootballPlayer previousPlayer;
  static public Club previousBallHolder;

  private int timeLeft;

  public int timerLength = 8;

  public MatchController(){
    previousPlayer = GameMaster.previousPlayer;
    previousBallHolder = GameMaster.previousBallHolder;
  }

  void Start(){
    startTime = Time.time;

    timerTextBox = GameObject.FindWithTag("Timer").GetComponent<TextMeshProUGUI>();
    matchTextBox = GameObject.FindWithTag("MatchText").GetComponent<TextMeshProUGUI>();
    scoreTextBox = GameObject.FindWithTag("Score").GetComponent<TextMeshProUGUI>();

    }

  void Update(){
    timeLeft = timerLength - (int)(Time.time - startTime);
    if(timeLeft == -1){
      startTime = Time.time;
      GameMaster.nextMatchEvent();
    }
    timerTextBox.text = timeLeft.ToString();

  }

  static public void updateMatchUI(Club currentBallHolder, int currentPosition, FootballPlayer currentPlayer){
    if(previousBallHolder != null){
      Debug.Log(previousBallHolder.getName());
    }
    if(previousPlayer != null){
      Debug.Log(previousPlayer.name);
    }
    Debug.Log(currentBallHolder.getName());
    Debug.Log(currentPlayer.name);
    if (same_team(currentBallHolder)){
      if (same_player(currentPlayer)){
        matchTextBox.text = (currentPlayer.name + " advances to position " +
                             currentPosition.ToString() + " for " + currentBallHolder.getName());
      }
      else {
        matchTextBox.text = (previousPlayer.name + " passes the ball to " +
                             currentPlayer.name + " at position " + currentPosition.ToString() + " for " +
                             currentBallHolder.getName());
      }
    }
    else {
      matchTextBox.text = (currentPlayer.name + " steals the ball from " + previousPlayer.name + " and advances to position " +
                           currentPosition.ToString() + " for " + currentBallHolder.getName());
    }
    GameMaster.previousPlayer = currentPlayer;
    GameMaster.previousBallHolder = currentBallHolder;
  }

  static public void updateMatchScore(string currentMatchScore, string goaler)
  {
    scoreTextBox.text = currentMatchScore;
    matchTextBox.text = "The club " + goaler + " scored a GOAL!\n The match will resume at 50m.";
  }

  private static bool same_team(Club ballHolder){
    if(previousBallHolder != null){
      if(previousBallHolder.getName() != ballHolder.getName()) return false;
    }
    return true;
  }

  private static bool same_player(FootballPlayer player){
    if(previousPlayer != null){
      if(previousPlayer.name != player.name) return false;
    }
    return true;
  }
}
