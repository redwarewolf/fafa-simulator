using System.Collections;
using System.Collections.Generic;
using System;
using UnityEngine;

public class Match : MonoBehaviour
{
  private Club myClub;

  private Club enemyClub;

  private int currentPosition = 50;
  private Club currentBallHolder;

  private int myClubScore;
  private int enemyClubScore;

  private int scoringChanceDividerConstant = 4;

  static private List<Event> randomEvents;

  public Match(Club amyClub, Club aenemyClub){
    myClub = amyClub;
    enemyClub = aenemyClub;

    Debug.Log(amyClub.getName());
    Debug.Log(aenemyClub.getName());

    }

  public void nextMatchEvent(){

    // Verificar si algún equipo está en posición de meter gol
    if(teamScores()){
      return;
    }

    // Si no sucede ningún evento random o algún Gol, entonces calculo los eventos normales
    calculateNormalEvent();

    MatchController.updateMatchUI(currentBallHolder,currentPosition);
  }

  private bool teamScores(){
    //Si estoy en posición de tiro al arco y meto gol
    if (currentPosition >= 90 && currentBallHolder == myClub && RandomCalculator.evaluateChances(myClubScoreChance() / scoringChanceDividerConstant))
    {
        myClubScore++;

        MatchController.updateMatchScore(myClubScore.ToString() + "-" + enemyClubScore.ToString(), currentBallHolder.getName());
        currentBallHolder = enemyClub;
        currentPosition = 50;
        return true;
    }

    //Si el equipo contrario está en posición de tiro al arco y mete gol

    if (currentPosition <= 10 && currentBallHolder == enemyClub && RandomCalculator.evaluateChances(myClubStopChance() / scoringChanceDividerConstant))
    {
        enemyClubScore++;

        MatchController.updateMatchScore(myClubScore.ToString() + "-" + enemyClubScore.ToString(), currentBallHolder.getName());
        currentBallHolder = myClub;
        currentPosition = 50;
        return true;
    }
    return false;
  }

  private bool matchPositionIsDef(){
    return currentPosition <= 35;
  }
  private bool matchPositionIsMid(){
    return currentPosition > 35 &&  currentPosition <= 70;
  }
  private bool matchPositionIsAtk(){
    return currentPosition > 70;
  }

  private void calculateNormalEvent(){

    // Si la posición es en la defensa:
    if (matchPositionIsDef())
    {
      calculateGoalKeeper(myClubStopChance());
    }
    // Sino, si la posición es en el medio campo:
    else if (matchPositionIsMid())
    {
      calculateGoalKeeper(myClubMidFieldChance());
    }
    //Sino, como la posición es ataque:
    else
    {
      calculateGoalKeeper(myClubScoreChance());
    }
  }

  private void calculateGoalKeeper(int chancesToEvaluate){
    if (RandomCalculator.evaluateChances(chancesToEvaluate)){
        currentBallHolder = myClub;
        currentPosition = Math.Min(95, currentPosition + 10);
    }
    else
    {
        currentBallHolder = enemyClub;
        currentPosition = Math.Max(5, currentPosition - 10);
    }
  }

  public int myClubMidFieldChance(){
    return (myClub.midfield() * 100) / (myClub.midfield() + enemyClub.midfield());
  }

  public int myClubScoreChance(){
    return (myClub.attacking() * 100) / (myClub.attacking() + enemyClub.defending() + enemyClub.goalkeeping());
  }

  public int myClubStopChance(){
    return ((myClub.defending() + myClub.goalkeeping()) * 100) / (myClub.defending() + myClub.goalkeeping() + enemyClub.attacking());
  }
}
