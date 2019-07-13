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

  private int timeLeft;

  public int timerLength = 8;

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

  static public void updateMatchUI(Club currentBallHolder, int currentPosition){
    matchTextBox.text = ("The team " + currentBallHolder.getName() + " has the ball at position " + currentPosition.ToString());
  }

  static public void updateMatchScore(string currentMatchScore, string goaler)
  {
    scoreTextBox.text = currentMatchScore;
    matchTextBox.text = "The club " + goaler + " scored a GOAL!\n The match will resume at 50m.";
  }
}
